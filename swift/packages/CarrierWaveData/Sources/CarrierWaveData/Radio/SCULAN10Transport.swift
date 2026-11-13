import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "SCULAN10Transport")

// MARK: - SCULAN10Transport

/// UDP transport for Yaesu SCU-LAN10 network remote control system.
/// Each UDP port runs its own dedicated receive task with an AsyncStream.
public actor SCULAN10Transport: RadioTransport {
    // MARK: Lifecycle

    public init(
        host: String,
        controlPort: UInt16 = 50_000,
        username: String,
        password: String,
        logCallback: (@Sendable (RadioCommandDirection, String) -> Void)? = nil,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) {
        self.host = host
        self.controlPort = controlPort
        self.username = username
        self.password = password
        self.logCallback = logCallback
        self.statusCallback = statusCallback

        let (catStream, catCont) = AsyncStream<Data>.makeStream()
        receivedData = catStream
        catContinuation = catCont

        let (scopeStream, scopeCont) = AsyncStream<Data>.makeStream()
        scopeData = scopeStream
        scopeContinuation = scopeCont

        let (audioStream, audioCont) = AsyncStream<Data>.makeStream()
        audioData = audioStream
        audioContinuation = audioCont
    }

    // MARK: Public

    nonisolated public let receivedData: AsyncStream<Data>
    nonisolated public let scopeData: AsyncStream<Data>
    /// Raw PCM samples (Int16 LE @ 16 kHz mono by default) extracted from the
    /// audio channel after stripping the transport header and 4-byte
    /// frame_seq/config prefix.
    nonisolated public let audioData: AsyncStream<Data>

    public var isConnected: Bool {
        connected
    }

    public var ctrlChanReceived: Int {
        ctrlChan?.totalReceived ?? 0
    }

    public var catChanReceived: Int {
        catChan?.totalReceived ?? 0
    }

    public var scopeChanReceived: Int {
        scopeChan?.totalReceived ?? 0
    }

    public var audioChanReceived: Int {
        audioChan?.totalReceived ?? 0
    }

    public var catChanSent: Int {
        catChan?.totalSent ?? 0
    }

    public var catSendErr: Int32 {
        catChan?.lastSendError ?? 0
    }

    public func connect() async throws {
        let targetHost = host
        let targetPort = controlPort
        logger.info("Connecting to SCU-LAN10 at \(targetHost):\(targetPort)")

        statusCallback?("Opening UDP connections…")
        createChannels()

        try ctrlChan!.start()
        try catChan!.start()
        try audioChan!.start()
        try scopeChan!.start()

        statusCallback?("Authenticating…")
        try await authenticate()

        connected = true
        statusCallback?("Connected")
        logCallback?(.status, "Connected to SCU-LAN10 at \(host)")

        ctrlChan?.enableStreaming()
        catChan?.enableStreaming()
        audioChan?.enableStreaming()
        scopeChan?.enableStreaming()

        startForwarding()
        startKeepaliveLoop()
    }

    public func disconnect() async {
        connected = false
        keepaliveTask?.cancel()
        forwardCatTask?.cancel()
        forwardScopeTask?.cancel()
        forwardAudioTask?.cancel()
        keepaliveTask = nil
        forwardCatTask = nil
        forwardScopeTask = nil
        forwardAudioTask = nil

        ctrlChan?.stop()
        catChan?.stop()
        audioChan?.stop()
        scopeChan?.stop()
        ctrlChan = nil
        catChan = nil
        audioChan = nil
        scopeChan = nil

        catContinuation.finish()
        scopeContinuation.finish()
        audioContinuation.finish()
        logger.info("SCU-LAN10 disconnected")
    }

    public func send(_ data: Data) async throws {
        guard let catChan, connected else {
            throw SCULAN10Error.notConnected
        }

        catCmdSeq &+= 1
        let prefix = Data([sessionId, 0, 0, 0, catCmdSeq, 0x00, 0x00, 0x00])
        let plaintext = prefix + data
        // Per docs/SCULAN10Protocol.md: every CAT command is sent twice
        // (with the same per-CAT cmd_seq) for UDP reliability. Both
        // packets share the cmd_seq so the radio dedups; per-channel
        // packet seq still increments to keep the wire-frame sequence
        // monotonic.
        let packet1 = SCULAN10Crypto.buildPacket(
            seq: nextSeq(for: .cat), channel: .cat,
            msgType: .data, plaintext: plaintext
        )
        let packet2 = SCULAN10Crypto.buildPacket(
            seq: nextSeq(for: .cat), channel: .cat,
            msgType: .data, plaintext: plaintext
        )
        catChan.send(packet1)
        catChan.send(packet2)

        let text = String(data: data, encoding: .ascii) ?? "<binary>"
        let trimmed = text.trimmingCharacters(in: .newlines)
        // Suppress poll commands so the command log shows operator
        // activity instead of the 1-Hz status sweep. Mirrors the RX-side
        // filter in `startCATForwarding`.
        let prefix2 = String(trimmed.prefix(2))
        if !["FA", "IF", "MD", "RI", "XI", "SS"].contains(prefix2) {
            logCallback?(.tx, trimmed)
        }
    }

    // MARK: Internal

    // Audio diagnostic capture (one-shot; written to ~/Downloads on the
    // 200th audio frame). Read/written by `SCULAN10Transport+Diagnostic`
    // (different file), so internal access is required.
    var captureRawBodies = Data()
    var capturePCMAfterHeader = Data()
    var captureFrameCount = 0
    var captureWritten = false

    // MARK: Private

    private let host: String
    private let controlPort: UInt16
    private let username: String
    private let password: String
    private let logCallback: (@Sendable (RadioCommandDirection, String) -> Void)?
    private let statusCallback: (@Sendable (String) -> Void)?
    private let catContinuation: AsyncStream<Data>.Continuation
    private let scopeContinuation: AsyncStream<Data>.Continuation
    private let audioContinuation: AsyncStream<Data>.Continuation

    private var ctrlChan: PortChannel?
    private var catChan: PortChannel?
    private var audioChan: PortChannel?
    private var scopeChan: PortChannel?

    private var connected = false
    private var sessionId: UInt8 = 0
    private var catCmdSeq: UInt8 = 0

    /// Per-channel sequence counters (start after init packets use 1-6).
    private var seqCtrl: UInt8 = 0x06
    private var seqCat: UInt8 = 0
    private var seqAudio: UInt8 = 0
    private var seqScope: UInt8 = 0

    private var keepaliveTask: Task<Void, Never>?
    private var forwardCatTask: Task<Void, Never>?
    private var forwardScopeTask: Task<Void, Never>?
    private var forwardAudioTask: Task<Void, Never>?

    private func nextSeq(for channel: SCULAN10Channel) -> UInt8 {
        switch channel {
        case .ctrl:
            seqCtrl &+= 1
            return seqCtrl
        case .cat:
            seqCat &+= 1
            return seqCat
        case .audio:
            seqAudio &+= 1
            return seqAudio
        case .scope:
            seqScope &+= 1
            return seqScope
        }
    }

    private func createChannels() {
        ctrlChan = PortChannel(host: host, port: controlPort)
        catChan = PortChannel(host: host, port: controlPort + 1)
        audioChan = PortChannel(host: host, port: controlPort + 2)
        scopeChan = PortChannel(host: host, port: controlPort + 3)

        let sc = statusCallback
        ctrlChan?.onError = { sc?("CTRL: \($0)") }
        catChan?.onError = { sc?("CAT: \($0)") }
        audioChan?.onError = { sc?("AUDIO: \($0)") }
        scopeChan?.onError = { sc?("SCOPE: \($0)") }

        catChan?.onReceive = { _ in
            // Scope/CAT raw packets are too frequent to log
        }
    }
}

// MARK: - Auth

extension SCULAN10Transport {
    private func authenticate() async throws {
        guard let ctrlChan else {
            throw SCULAN10Error.notConnected
        }

        // Phase 1: Send 5 fixed init keepalives
        statusCallback?("Sending handshake…")
        for pkt in SCULAN10Crypto.initPackets {
            ctrlChan.send(pkt)
        }

        // Phase 2: Send auth packet
        statusCallback?("Sending credentials…")
        ctrlChan.send(SCULAN10Crypto.buildAuthPacket(
            username: username, password: password
        ))

        // Phase 3: Wait for auth response
        statusCallback?("Waiting for auth response…")
        guard let response = await ctrlChan.receive(timeout: 5.0),
              response.count >= 6
        else {
            throw SCULAN10Error.authFailed
        }

        let decrypted = SCULAN10Crypto.decryptPayload(
            Data(response.dropFirst(6))
        )
        sessionId = decrypted[0]
        let sid = sessionId
        statusCallback?("Authenticated (session 0x\(String(format: "%02X", sid)))")

        // Phase 4: Post-auth channel setup
        try await setupChannels()
    }

    private func setupChannels() async throws {
        // Continuation: tell server we're connecting (channel=0xFD, type=setup)
        sendSetupPacket(
            to: ctrlChan, channel: .cat, msgType: .setup,
            payload: Data([sessionId, 0, 0, 0, 0x51, 0xC3, 0x00, 0x96, 0, 0])
        )
        try await waitForAck("continuation")

        // CAT port (50001): init on port + setup on ctrl
        statusCallback?("Initializing CAT port…")
        sendPortInit(catChan, channel: .cat)
        sendSetupPacket(
            to: ctrlChan, channel: .audio, msgType: .setup,
            payload: Data([sessionId, 0, 0, 0, 0x52, 0xC3])
        )
        try await waitForAck("CAT")

        // Audio port (50002): init on port + setup on ctrl
        statusCallback?("Initializing Audio port…")
        sendPortInit(audioChan, channel: .audio)
        sendSetupPacket(
            to: ctrlChan, channel: .scope, msgType: .setup,
            payload: Data([sessionId, 0, 0, 0, 0x53, 0xC3])
        )
        try await waitForAck("Audio")

        // Scope port (50003): init on port only (no ctrl setup needed)
        statusCallback?("Initializing Scope port…")
        sendPortInit(scopeChan, channel: .scope)

        // Initial keepalives on all channels
        sendKeepalive(ctrlChan, channel: .ctrl)
        sendKeepalive(audioChan, channel: .audio)
        sendKeepalive(scopeChan, channel: .scope)
        sendKeepalive(catChan, channel: .cat)
    }

    private func sendPortInit(
        _ chan: PortChannel?, channel: SCULAN10Channel
    ) {
        guard let chan else {
            return
        }
        let pkt = SCULAN10Crypto.buildPacket(
            seq: nextSeq(for: channel), channel: channel,
            msgType: .portInit,
            plaintext: Data([sessionId, 0, 0, 0])
        )
        chan.send(pkt)
    }

    private func sendSetupPacket(
        to chan: PortChannel?,
        channel: SCULAN10Channel,
        msgType: SCULAN10MsgType,
        payload: Data
    ) {
        guard let chan else {
            return
        }
        let pkt = SCULAN10Crypto.buildPacket(
            seq: nextSeq(for: .ctrl), channel: channel,
            msgType: msgType, plaintext: payload
        )
        chan.send(pkt)
    }

    private func waitForAck(_ label: String) async throws {
        statusCallback?("Waiting for \(label) ack…")
        // Server responds with acks within ~150ms
        try? await Task.sleep(for: .milliseconds(200))
    }
}

// MARK: - Forwarding & Keepalive

extension SCULAN10Transport {
    private func startForwarding() {
        startCATForwarding(catChan?.inbound)
        startScopeForwarding(scopeChan?.inbound)
        startAudioForwarding(audioChan?.inbound)
    }

    private func startCATForwarding(_ inbound: AsyncStream<Data>?) {
        let catLog = logCallback
        let catCont = catContinuation
        forwardCatTask = Task {
            guard let inbound else {
                return
            }
            for await data in inbound {
                guard !Task.isCancelled else {
                    break
                }
                guard data.count > 6 else {
                    continue
                }
                let dec = SCULAN10Crypto.decryptPayload(Data(data.dropFirst(6)))
                guard dec.count > 4 else {
                    continue
                }
                let catData = Data(dec.dropFirst(4))
                guard !catData.isEmpty else {
                    continue
                }
                let text = String(data: catData, encoding: .ascii) ?? "<binary>"
                let trimmed = text.trimmingCharacters(in: .newlines)
                // Skip high-frequency poll responses (FA/IF/MD/RI/XI/SS) from log
                let prefix2 = String(trimmed.prefix(2))
                if !["FA", "IF", "MD", "RI", "XI", "SS"].contains(prefix2) {
                    catLog?(.rx, trimmed)
                }
                catCont.yield(catData)
            }
        }
    }

    private func startAudioForwarding(_ inbound: AsyncStream<Data>?) {
        let audioCont = audioContinuation
        let audioLog = logCallback
        let audioStatus: @Sendable (String) -> Void = { msg in
            audioLog?(.status, msg)
        }
        forwardAudioTask = Task {
            guard let inbound else {
                return
            }
            var frameIndex = 0
            for await data in inbound {
                guard !Task.isCancelled else {
                    break
                }
                // 24 B inner header + 640 B stereo Int16 LE @ 16 kHz;
                // see docs/SCULAN10Protocol.md "Audio Data".
                guard data.count > 6 else {
                    continue
                }
                let dec = SCULAN10Crypto.decryptPayload(Data(data.dropFirst(6)))
                guard dec.count > Self.audioInnerHeaderBytes else {
                    continue
                }
                if frameIndex < 8 || frameIndex == 100 || frameIndex == 200 {
                    Self.dumpAudioFrame(
                        index: frameIndex,
                        decrypted: dec,
                        status: audioStatus
                    )
                }
                self.appendCapture(decrypted: dec, status: audioStatus)
                frameIndex &+= 1
                let stereo = Data(dec.dropFirst(Self.audioInnerHeaderBytes))
                guard !stereo.isEmpty else {
                    continue
                }
                // De-interleave to mono Ch0 so all consumers see the same
                // stream and the wire bytes to Field halve.
                audioCont.yield(Self.extractLeftChannel(fromStereo: stereo))
            }
        }
    }

    private func startScopeForwarding(_ inbound: AsyncStream<Data>?) {
        let scopeCont = scopeContinuation
        forwardScopeTask = Task {
            guard let inbound else {
                return
            }
            for await data in inbound {
                guard !Task.isCancelled else {
                    break
                }
                guard data.count >= 4_110 else {
                    continue
                }
                let payload = Data(data.dropFirst(6))
                guard payload.count >= 4_104 else {
                    continue
                }
                scopeCont.yield(SCULAN10Crypto.decryptScopeData(payload))
            }
        }
    }

    private func startKeepaliveLoop() {
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else {
                    break
                }
                await sendKeepalive(ctrlChan, channel: .ctrl)
                await sendKeepalive(catChan, channel: .cat)
                await sendKeepalive(audioChan, channel: .audio)
                await sendKeepalive(scopeChan, channel: .scope)
            }
        }
    }

    private func sendKeepalive(
        _ chan: PortChannel?, channel: SCULAN10Channel
    ) {
        guard let chan else {
            return
        }
        let pkt = SCULAN10Crypto.buildPacket(
            seq: nextSeq(for: channel), channel: channel,
            msgType: .keepalive,
            plaintext: Data([0, 0, 0, 0])
        )
        chan.send(pkt)
    }
}
