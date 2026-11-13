import CarrierWaveCore
import Foundation

// MARK: - IcomWiFiConfig

/// Configuration for connecting to an Icom radio over WiFi (RS-BA1 protocol).
public struct IcomWiFiConfig: Sendable {
    // MARK: Lifecycle

    public init(
        ipAddress: String = "192.168.59.1",
        username: String,
        password: String
    ) {
        self.ipAddress = ipAddress
        self.username = username
        self.password = password
    }

    // MARK: Public

    public let ipAddress: String
    public let username: String
    public let password: String

    /// Preset for IC-705 WiFi access point mode (default IP).
    public static func accessPoint(
        username: String, password: String
    ) -> IcomWiFiConfig {
        IcomWiFiConfig(
            ipAddress: "192.168.59.1",
            username: username,
            password: password
        )
    }
}

// MARK: - IcomWiFiTransport

/// RS-BA1 UDP transport for Icom WiFi-capable radios (IC-705, IC-7610, etc.).
/// Protocol reconstructed from kappanhang (Go) and icom-lan (Python).
public actor IcomWiFiTransport: RadioTransport {
    // MARK: Lifecycle

    public init(
        config: IcomWiFiConfig,
        onLog: (@Sendable (String, Data?) -> Void)? = nil
    ) {
        self.config = config
        self.onLog = onLog

        let (strm, cont) = AsyncStream<Data>.makeStream()
        receivedData = strm
        civContinuation = cont
        let (scopeStrm, scopeCont) = AsyncStream<CIVScopeFrame>.makeStream()
        scopeFrames = scopeStrm
        scopeContinuation = scopeCont
    }

    // MARK: Public

    /// CI-V bytes for the CAT session, with `27 00` scope waveform frames
    /// already removed (see `demuxCIV`).
    nonisolated public let receivedData: AsyncStream<Data>

    /// Spectrum scope waveform frames (`27 00`). Only flows after the client
    /// sends `27 11 01`; on the IC-9700 each frame is tagged Main or Sub.
    nonisolated public let scopeFrames: AsyncStream<CIVScopeFrame>

    /// WiFi CI-V needs slower polling — radio firmware can't handle BLE-rate commands.
    nonisolated public let recommendedPollInterval: Duration = .seconds(1)

    public var isConnected: Bool {
        connected
    }

    public func send(_ data: Data) async throws {
        guard connected, let civChannel else {
            throw IcomWiFiError.notConnected
        }
        var packet = buildCIVDataPacket(payload: data)
        sendTracked(&packet, channel: civChannel, isCIV: true)
    }

    public func connect() async throws {
        let control = UDPChannel(host: config.ipAddress, port: RSBA1Ports.control)
        let civ = UDPChannel(host: config.ipAddress, port: RSBA1Ports.serial)
        try control.start()
        try civ.start()
        controlChannel = control
        civChannel = civ
        localSID = deriveSessionID(localPort: control.localPort)

        do {
            try await authenticate()
        } catch {
            // Auth failed. Stop the channels so their receive threads exit —
            // otherwise every failed connect leaks two POSIX threads + sockets,
            // and the recv loops can pin CPU on persistent ICMP unreachable
            // when the radio isn't actually on the network.
            control.stop()
            civ.stop()
            controlChannel = nil
            civChannel = nil
            throw error
        }

        // Enable streaming on both channels AFTER auth completes.
        // Control channel was switched to streaming inside authenticate();
        // CIV channel switches here before starting the forward loop.
        civ.enableStreaming()
        connected = true
        keepaliveTask = Task { [weak self] in await self?.keepaliveLoop() }
        civForwardTask = Task { [weak self] in await self?.civForwardLoop() }
        controlForwardTask = Task { [weak self] in await self?.controlForwardLoop() }
    }

    public func disconnect() async {
        log("disconnect: begin", nil)
        connected = false

        // Stop loops first so they don't send more packets
        keepaliveTask?.cancel()
        keepaliveTask = nil
        civForwardTask?.cancel()
        civForwardTask = nil
        controlForwardTask?.cancel()
        controlForwardTask = nil

        // Close CIV session so the radio releases it for the next connection
        if let civChannel {
            log("TX CIV close", nil)
            var closePkt = buildCIVClosePacket()
            sendTracked(&closePkt, channel: civChannel, isCIV: true)
            try? await Task.sleep(for: .milliseconds(100))
        }

        if let controlChannel {
            log("TX deauth(0x01) + pkt5 x2", nil)
            var deauth = buildAuthPacket(magic: 0x01)
            sendTracked(&deauth, channel: controlChannel)
            try? await Task.sleep(for: .milliseconds(100))
            let pkt5 = buildPkt5()
            controlChannel.send(pkt5)
            controlChannel.send(pkt5)
            try? await Task.sleep(for: .milliseconds(500))
        }

        controlChannel?.stop()
        civChannel?.stop()
        controlChannel = nil
        civChannel = nil
        civContinuation.finish()
        scopeContinuation.finish()
        log("disconnect: complete", nil)
    }

    // MARK: Internal

    var localSID: UInt32 = 0
    var remoteSID: UInt32 = 0
    var civRemoteSID: UInt32 = 0
    var authID = Data(count: 6)
    var authInnerSeq: UInt16 = 0
    var trackedSeq: UInt16 = 1
    var civTrackedSeq: UInt16 = 1
    var civDataSeq: UInt16 = 0
    var pingSeq: UInt16 = 2
    var a8ReplyID = Data(count: 16)
    var txBuffer: [UInt16: Data] = [:]
    let maxTxBufferSize = 64

    let config: IcomWiFiConfig
    let onLog: (@Sendable (String, Data?) -> Void)?
    let civContinuation: AsyncStream<Data>.Continuation
    let scopeContinuation: AsyncStream<CIVScopeFrame>.Continuation

    /// Partial CI-V frame bytes carried over between UDP packets.
    var civBuffer: [UInt8] = []

    var controlChannel: UDPChannel?
    var civChannel: UDPChannel?
    var connected = false

    var controlForwardTask: Task<Void, Never>?

    // MARK: Private

    private var keepaliveTask: Task<Void, Never>?
    private var civForwardTask: Task<Void, Never>?
    private var lastPkt7Reply = Date()
    private var lastReauthTime = Date()
    private let reauthInterval: TimeInterval = 55
}

// MARK: - Keepalive

extension IcomWiFiTransport {
    /// Sends periodic pkt7 pings and idle packets to keep the session alive.
    /// Checks `lastPkt7Reply` (set by `controlForwardLoop`) for liveness.
    func keepaliveLoop() async {
        // Reset so the 10s timeout counts from connection, not transport init
        lastPkt7Reply = Date()
        lastReauthTime = Date()
        var lastCycleTime = Date()
        while !Task.isCancelled, connected {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, connected, let controlChannel else {
                break
            }

            // Detect app suspension: if sleep took >>3s, iOS suspended us.
            // Reset liveness timer and immediately reauth to reclaim the session.
            let sleepDuration = Date().timeIntervalSince(lastCycleTime)
            if sleepDuration > 6 {
                lastPkt7Reply = Date()
                var reauth = buildAuthPacket(magic: 0x05)
                log("TX reauth(0x05) [resume from \(Int(sleepDuration))s suspend]", reauth)
                sendTracked(&reauth, channel: controlChannel)
                lastReauthTime = Date()
            }
            lastCycleTime = Date()

            controlChannel.send(buildPkt7Request())

            // Check if controlForwardLoop has seen a pkt7 reply recently
            let elapsed = Date().timeIntervalSince(lastPkt7Reply)
            if elapsed > 10 {
                log("keepalive timeout — no pkt7 reply for \(Int(elapsed))s, disconnecting", nil)
                connected = false
                controlChannel.stop()
                civChannel?.stop()
                civContinuation.finish()
                scopeContinuation.finish()
                break
            }

            var idlePkt = buildIdlePacket()
            sendTracked(&idlePkt, channel: controlChannel)
            if let civChannel {
                var civIdle = buildCIVIdlePacket()
                sendTracked(&civIdle, channel: civChannel, isCIV: true)
            }

            // Reauth every 55s — radio kills sessions without periodic auth(0x05)
            let sinceReauth = Date().timeIntervalSince(lastReauthTime)
            if sinceReauth >= reauthInterval {
                var reauth = buildAuthPacket(magic: 0x05)
                log("TX reauth(0x05) [periodic, \(Int(sinceReauth))s since last]", reauth)
                sendTracked(&reauth, channel: controlChannel)
                lastReauthTime = Date()
            }
        }
    }

    /// Consumes control channel streaming packets: replies to pkt7,
    /// handles retransmit requests, tracks liveness via `lastPkt7Reply`.
    func controlForwardLoop() async {
        guard let controlChannel else {
            return
        }
        for await packet in controlChannel.inbound {
            guard !Task.isCancelled else {
                break
            }
            guard packet.count >= 16 else {
                continue
            }

            // Reply to pkt7 pings from the radio
            if packet.count == 21, packet[4] == 0x07, packet[16] == 0x00 {
                var reply = packet
                reply[16] = 0x01
                writeUInt32BE(&reply, offset: 8, value: localSID)
                writeUInt32BE(&reply, offset: 12, value: remoteSID)
                controlChannel.send(reply)
                continue
            }

            // Track pkt7 replies (liveness indicator)
            if packet.count == 21, packet[4] == 0x07, packet[16] == 0x01 {
                lastPkt7Reply = Date()
                continue
            }

            // Handle retransmit requests
            if packet[4] == 0x01 {
                handleRetransmit(packet, channel: controlChannel)
                continue
            }

            // Radio-initiated disconnect
            if packet[4] == 0x05 {
                log("RX ctrl pkt5 (disconnect from radio)", nil)
            }
        }
    }

    /// Forwards CI-V data from the CIV channel to the receivedData stream.
    /// Replies to pkt7 and handles retransmit on the CIV channel.
    func civForwardLoop() async {
        guard let civChannel else {
            return
        }
        for await packet in civChannel.inbound {
            guard !Task.isCancelled else {
                break
            }
            guard packet.count >= 16 else {
                continue
            }

            if packet.count > 21, packet[16] == 0xC1 {
                demuxCIV(packet.subdata(in: 21 ..< packet.count))
            }
            if packet.count == 21, packet[4] == 0x07, packet[16] == 0x00 {
                var reply = packet
                reply[16] = 0x01
                writeUInt32BE(&reply, offset: 8, value: localSID)
                writeUInt32BE(&reply, offset: 12, value: civRemoteSID)
                civChannel.send(reply)
            }
            if packet[4] == 0x01 {
                handleRetransmit(packet, channel: civChannel)
            }
            if packet[4] == 0x05 {
                log("RX CIV pkt5 (disconnect from radio)", nil)
            }
        }
    }

    /// Split the CI-V byte stream: `27 00` waveform frames go to `scopeFrames`,
    /// every other frame is re-serialized onto `receivedData`. Keeps the CAT
    /// session (and its command log) from wading through ~500-byte scope
    /// payloads at scope refresh rate.
    func demuxCIV(_ chunk: Data) {
        civBuffer.append(contentsOf: chunk)
        let result = CIVProtocol.extractFrames(from: civBuffer)
        civBuffer.removeFirst(min(result.consumed, civBuffer.count))
        if civBuffer.count > maxCIVBufferSize {
            // Nothing frame-shaped in a long stretch of bytes; drop it.
            civBuffer.removeAll(keepingCapacity: true)
        }

        var passthrough: [UInt8] = []
        for frame in result.frames {
            if let scope = CIVScopeFrame(frame: frame) {
                scopeContinuation.yield(scope)
            } else {
                passthrough += CIVProtocol.buildFrame(
                    to: frame.to, from: frame.from, command: frame.command, data: frame.data
                )
            }
        }
        if !passthrough.isEmpty {
            civContinuation.yield(Data(passthrough))
        }
    }
}

private let maxCIVBufferSize = 4_096
