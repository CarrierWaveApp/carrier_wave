import CarrierWaveData
import Foundation

// MARK: - KiwiSDRClient

/// WebSocket client for connecting to KiwiSDR receivers.
/// Handles protocol handshake, tuning commands, and audio streaming.
actor KiwiSDRClient {
    // MARK: Lifecycle

    init(host: String, port: Int = 8_073) {
        self.host = host
        self.port = port
    }

    deinit {
        keepAliveTask?.cancel()
    }

    // MARK: Internal

    /// Audio frame received from the KiwiSDR
    struct AudioFrame {
        let samples: [Int16]
        let sampleRate: Double
        let sMeter: UInt16
        let timestamp: Date
    }

    /// Connection state
    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
        case streaming
        case error(String)
    }

    /// Current connection state
    var currentState: ConnectionState {
        state
    }

    /// Current S-meter reading
    var currentSMeter: UInt16 {
        lastSMeter
    }

    /// Negotiated sample rate from the server handshake
    var negotiatedSampleRate: Double {
        sampleRate
    }

    /// Connect and start receiving audio. Returns an AsyncStream of audio frames.
    func connect(
        frequencyKHz: Double,
        mode: KiwiSDRMode,
        password: String? = nil
    ) async throws -> AsyncStream<AudioFrame> {
        guard webSocket == nil else {
            throw KiwiSDRError.alreadyConnected
        }

        state = .connecting
        targetFrequency = frequencyKHz
        targetMode = mode

        let timestamp = Int(Date().timeIntervalSince1970)
        let urlString = "ws://\(host):\(port)/\(timestamp)/SND"
        guard let url = URL(string: urlString) else {
            throw KiwiSDRError.invalidURL
        }

        let session = URLSession(configuration: .default)
        urlSession = session
        let ws = session.webSocketTask(with: url)
        webSocket = ws
        ws.resume()

        // Send auth
        let authPassword = password ?? "#"
        try await send("SET auth t=kiwi p=\(authPassword)")

        // Wait for sample_rate message
        sampleRate = try await waitForSampleRate()

        // Acknowledge, identify, and configure
        let inRate = Int(sampleRate)
        try await send("SET AR OK in=\(inRate) out=\(inRate)")
        try await send("SET ident_user=CarrierWave")
        try await send("SET compression=1")

        // Tune to requested frequency and mode
        try await tune(frequencyKHz: frequencyKHz, mode: mode)

        // Set AGC
        try await send("SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50")

        state = .connected

        // Start keep-alive timer
        startKeepAlive()

        // Create audio stream
        let stream = AsyncStream<AudioFrame> { continuation in
            self.audioContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.disconnect() }
            }
        }

        // Start receiving messages
        receiveTask = Task { await receiveLoop() }

        state = .streaming
        return stream
    }

    /// Disconnect from the KiwiSDR
    func disconnect() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        receiveTask?.cancel()
        receiveTask = nil

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        audioContinuation?.finish()
        audioContinuation = nil

        adpcmState = KiwiSDRADPCM.DecoderState()
        state = .disconnected
    }

    /// Retune to a new frequency
    func retune(frequencyKHz: Double) async throws {
        targetFrequency = frequencyKHz
        try await tune(frequencyKHz: frequencyKHz, mode: targetMode)
    }

    /// Change mode
    func changeMode(_ mode: KiwiSDRMode) async throws {
        targetMode = mode
        try await tune(frequencyKHz: targetFrequency, mode: mode)
    }

    // MARK: Private

    private let host: String
    private let port: Int

    private var urlSession: URLSession?
    private var webSocket: URLSessionWebSocketTask?
    private var audioContinuation: AsyncStream<AudioFrame>.Continuation?
    private var sampleRate: Double = 12_000
    private var state: ConnectionState = .disconnected

    private var targetFrequency: Double = 14_060
    private var targetMode: KiwiSDRMode = .cw

    private var adpcmState = KiwiSDRADPCM.DecoderState()
    private var lastSMeter: UInt16 = 0

    private var keepAliveTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private func send(_ message: String) async throws {
        guard let ws = webSocket else {
            throw KiwiSDRError.notConnected
        }
        try await ws.send(.string(message))
    }

    private func tune(frequencyKHz: Double, mode: KiwiSDRMode) async throws {
        let carrierKHz = frequencyKHz - mode.carrierOffsetKHz
        let cmd = "SET mod=\(mode.kiwiName) "
            + "low_cut=\(mode.lowCut) high_cut=\(mode.highCut) "
            + "freq=\(String(format: "%.3f", carrierKHz))"
        try await send(cmd)
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            // Send first keepalive immediately, then every 5 seconds
            while !Task.isCancelled {
                try? await self?.send("SET keepalive")
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Wait for the server's sample_rate message during handshake
    private func waitForSampleRate() async throws -> Double {
        guard let ws = webSocket else {
            throw KiwiSDRError.notConnected
        }

        // Read messages until we get sample_rate or a server error.
        // KiwiSDR sends MSG text as binary WebSocket frames, so we
        // must check both text and binary frames for MSG content.
        for _ in 0 ..< 30 {
            let text = try await receiveText(from: ws)
            guard let text else {
                continue
            }

            try checkForServerError(text)

            if let rate = parseSampleRate(text) {
                return rate
            }
        }

        throw KiwiSDRError.handshakeFailed("No sample_rate received")
    }

    /// Receive a WebSocket message and extract text content.
    /// KiwiSDR sends MSG text as binary frames, so this decodes
    /// binary data as UTF-8 when it doesn't start with "SND".
    private func receiveText(
        from ws: URLSessionWebSocketTask
    ) async throws -> String? {
        let message = try await ws.receive()
        switch message {
        case let .string(text):
            return text
        case let .data(data):
            // Skip audio frames (start with "SND")
            if data.count >= 3,
               data[0] == 0x53, data[1] == 0x4E, data[2] == 0x44
            {
                return nil
            }
            return String(data: data, encoding: .utf8)
        @unknown default:
            return nil
        }
    }

    private func parseSampleRate(_ message: String) -> Double? {
        parseMSGValue(message, key: "sample_rate").flatMap { Double($0) }
    }

    /// Extract a value for a key from a "MSG key=value key2=value2" message.
    private func parseMSGValue(_ message: String, key: String) -> String? {
        guard message.contains("\(key)=") else {
            return nil
        }
        let parts = message.components(separatedBy: "\(key)=")
        guard parts.count > 1 else {
            return nil
        }
        return parts[1].components(separatedBy: " ").first ?? parts[1]
    }

    /// Check a server message for error conditions and throw if found.
    private func checkForServerError(_ message: String) throws {
        if let badp = parseMSGValue(message, key: "badp"),
           let code = Int(badp), code != 0
        {
            throw KiwiSDRError.authenticationFailed
        }

        if let busyStr = parseMSGValue(message, key: "too_busy"),
           let slots = Int(busyStr), slots > 0
        {
            throw KiwiSDRError.tooBusy(slots)
        }

        if message.contains("MSG down") {
            throw KiwiSDRError.serverDown
        }

        if let redirect = parseMSGValue(message, key: "redirect") {
            throw KiwiSDRError.serverRedirect(redirect)
        }
    }
}

// MARK: - Receive Loop & Message Processing

extension KiwiSDRClient {
    /// Main receive loop for WebSocket messages
    func receiveLoop() async {
        guard let ws = webSocket else {
            return
        }

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case let .data(data):
                    // KiwiSDR sends MSG text as binary frames.
                    // Route based on "SND" header vs text content.
                    if data.count >= 3,
                       data[0] == 0x53, data[1] == 0x4E, data[2] == 0x44
                    {
                        processAudioData(data)
                    } else if let text = String(data: data, encoding: .utf8) {
                        processTextMessage(text)
                    }
                case let .string(text):
                    processTextMessage(text)
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    state = .error(error.localizedDescription)
                    audioContinuation?.finish()
                }
                return
            }
        }
    }

    /// Process a binary audio frame from the KiwiSDR
    private func processAudioData(_ data: Data) {
        // Minimum frame: "SND" (3) + flags (1) + seq (4) + smeter (2) = 10 bytes
        guard data.count >= 10 else {
            return
        }

        // Verify "SND" header
        guard data[0] == 0x53, data[1] == 0x4E, data[2] == 0x44 else {
            return
        }

        let flags = data[3]
        let isCompressed = (flags & 0x10) != 0
        let isLittleEndian = (flags & 0x80) != 0
        let isIQ = (flags & 0x08) != 0

        // We only handle mono modes for recording
        guard !isIQ else {
            return
        }

        // Parse S-meter (big-endian UInt16 at offset 8)
        lastSMeter = UInt16(data[8]) << 8 | UInt16(data[9])

        // Audio data starts at offset 10
        let audioData = data.subdata(in: 10 ..< data.count)
        guard !audioData.isEmpty else {
            return
        }

        let samples: [Int16] = if isCompressed {
            KiwiSDRADPCM.decode(audioData, state: &adpcmState)
        } else {
            parsePCM(audioData, littleEndian: isLittleEndian)
        }

        guard !samples.isEmpty else {
            return
        }

        let frame = AudioFrame(
            samples: samples,
            sampleRate: sampleRate,
            sMeter: lastSMeter,
            timestamp: Date()
        )

        audioContinuation?.yield(frame)
    }

    /// Parse raw PCM Int16 samples from data
    private func parsePCM(_ data: Data, littleEndian: Bool) -> [Int16] {
        let sampleCount = data.count / 2
        var samples: [Int16] = []
        samples.reserveCapacity(sampleCount)

        for i in 0 ..< sampleCount {
            let offset = i * 2
            let sample = if littleEndian {
                Int16(data[offset]) | Int16(data[offset + 1]) << 8
            } else {
                Int16(data[offset]) << 8 | Int16(data[offset + 1])
            }
            samples.append(sample)
        }

        return samples
    }

    private func processTextMessage(_ text: String) {
        // Check for ADPCM state resets from the server
        if let adpcmStr = parseMSGValue(text, key: "audio_adpcm_state") {
            let parts = adpcmStr.split(separator: ",")
            if parts.count == 2,
               let index = Int(parts[0]),
               let prev = Int32(parts[1])
            {
                adpcmState.stepIndex = max(0, min(88, index))
                adpcmState.predictor = prev
            }
        }

        // Detect server redirect and finish stream so session can reconnect
        if parseMSGValue(text, key: "redirect") != nil {
            state = .error("Server redirect")
            audioContinuation?.finish()
            return
        }

        // Detect server-initiated disconnect
        // Note: "too_busy=0" is an informational status (not busy), not a disconnect.
        let isTooBusy = if let busyStr = parseMSGValue(text, key: "too_busy"),
                           let slots = Int(busyStr)
        {
            slots > 0
        } else {
            false
        }
        if isTooBusy || text.contains("MSG down") ||
            text.contains("MSG inactivity_timeout")
        {
            state = .error("Server disconnected: \(text)")
            audioContinuation?.finish()
        }
    }
}
