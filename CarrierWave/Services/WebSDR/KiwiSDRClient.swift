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

        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let urlString = "ws://\(host):\(port)/kiwi/\(timestamp)/SND"
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

        // Acknowledge and identify
        let inRate = Int(sampleRate)
        try await send("SET AR OK in=\(inRate) out=\(inRate)")
        try await send("SERVER DE CLIENT CarrierWave SND")

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
        let cmd = "SET mod=\(mode.kiwiName) "
            + "low_cut=\(mode.lowCut) high_cut=\(mode.highCut) "
            + "freq=\(String(format: "%.3f", frequencyKHz))"
        try await send(cmd)
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else {
                    return
                }
                try? await self?.send("SET keepalive")
            }
        }
    }

    /// Wait for the server's sample_rate message during handshake
    private func waitForSampleRate() async throws -> Double {
        guard let ws = webSocket else {
            throw KiwiSDRError.notConnected
        }

        // Read messages until we get sample_rate (with timeout)
        for _ in 0 ..< 20 {
            let message = try await ws.receive()
            if case let .string(text) = message {
                if let rate = parseSampleRate(text) {
                    return rate
                }
            }
        }

        throw KiwiSDRError.handshakeFailed("No sample_rate received")
    }

    private func parseSampleRate(_ message: String) -> Double? {
        // Format: "MSG sample_rate=12000.000000"
        guard message.contains("sample_rate=") else {
            return nil
        }
        let parts = message.components(separatedBy: "sample_rate=")
        guard parts.count > 1 else {
            return nil
        }
        let valueStr = parts[1].components(separatedBy: " ").first ?? parts[1]
        return Double(valueStr)
    }

    /// Main receive loop for WebSocket messages
    private func receiveLoop() async {
        guard let ws = webSocket else {
            return
        }

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case let .data(data):
                    processAudioData(data)
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
        // Handle server messages (auth results, status updates, etc.)
        // Currently we only need sample_rate which is handled during handshake
    }
}

// MARK: - KiwiSDRMode

/// Radio modes supported by KiwiSDR, mapped from amateur radio modes.
/// Explicitly nonisolated — pure value type used across actor boundaries.
nonisolated enum KiwiSDRMode: Sendable {
    case cw
    case usb
    case lsb
    case am
    case nbfm

    // MARK: Internal

    /// KiwiSDR protocol name for this mode
    var kiwiName: String {
        switch self {
        case .cw: "cw"
        case .usb: "usb"
        case .lsb: "lsb"
        case .am: "am"
        case .nbfm: "nbfm"
        }
    }

    /// Low frequency cut in Hz
    var lowCut: Int {
        switch self {
        case .cw: 200
        case .usb: 300
        case .lsb: -2_700
        case .am: -5_000
        case .nbfm: -6_000
        }
    }

    /// High frequency cut in Hz
    var highCut: Int {
        switch self {
        case .cw: 1_000
        case .usb: 2_700
        case .lsb: -300
        case .am: 5_000
        case .nbfm: 6_000
        }
    }

    /// Map from Carrier Wave mode string to KiwiSDR mode
    static func from(carrierWaveMode: String, frequencyMHz: Double?) -> KiwiSDRMode {
        switch carrierWaveMode.uppercased() {
        case "CW":
            return .cw
        case "SSB":
            // SSB → USB above 10 MHz, LSB below
            if let freq = frequencyMHz, freq < 10.0 {
                return .lsb
            }
            return .usb
        case "USB":
            return .usb
        case "LSB":
            return .lsb
        case "FT8",
             "FT4",
             "RTTY",
             "DATA",
             "DIGITAL",
             "PSK31",
             "PSK",
             "JT65",
             "JT9",
             "WSPR":
            return .usb
        case "AM":
            return .am
        case "FM":
            return .nbfm
        default:
            return .usb
        }
    }
}

// MARK: - KiwiSDRError

nonisolated enum KiwiSDRError: Error, LocalizedError {
    case invalidURL
    case notConnected
    case alreadyConnected
    case handshakeFailed(String)
    case connectionLost

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid KiwiSDR URL"
        case .notConnected:
            "Not connected to KiwiSDR"
        case .alreadyConnected:
            "Already connected to a KiwiSDR"
        case let .handshakeFailed(reason):
            "KiwiSDR handshake failed: \(reason)"
        case .connectionLost:
            "Connection to KiwiSDR lost"
        }
    }
}
