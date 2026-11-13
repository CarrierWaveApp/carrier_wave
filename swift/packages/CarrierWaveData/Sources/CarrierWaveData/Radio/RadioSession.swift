import Foundation

/// Transport-agnostic radio session that polls frequency/mode and publishes state.
public actor RadioSession {
    // MARK: Lifecycle

    public init(
        transport: any RadioTransport,
        protocolHandler: any RadioProtocolHandler,
        frameType: FrameAssembler.FrameType = .civ
    ) {
        self.transport = transport
        self.protocolHandler = protocolHandler
        frameAssembler = FrameAssembler(frameType: frameType)
    }

    // MARK: Public

    public struct RadioState: Sendable {
        // MARK: Lifecycle

        public init() {}

        // MARK: Public

        public var frequency: Double = 0
        public var mode: String = ""
        public var isTransmitting: Bool = false
        public var isConnected: Bool = false
        public var xitEnabled: Bool = false
        public var ritEnabled: Bool = false
        public var ritXitOffset: Int = 0
        public var powerLevel: UInt8 = 0
    }

    public private(set) var state = RadioState()

    /// Set to true for push-based radios (e.g. FlexRadio) that don't need polling.
    public var skipPolling: Bool = false

    /// Force slow polling (one command per cycle at 500ms) for radios like the
    /// FT-891 that click when CAT commands arrive faster than 50ms apart.
    public var useSlowPolling: Bool = false

    /// Called with each raw received frame for protocol-specific processing by callers.
    public var onRawFrame: (@Sendable (Data) -> Void)?

    /// Secondary frame observer for codec-level hardware tests. Independent of
    /// `onRawFrame` so the codec-over-serial harness can run alongside the
    /// existing slot tracker that owns `onRawFrame`.
    public var codecTap: (@Sendable (Data) -> Void)?

    /// True iff the active protocol handler can encode a CW string. Lets
    /// callers gate UI without speculatively encoding a sentinel string.
    public var supportsCATKeying: Bool {
        protocolHandler.encodeSendCW("E") != nil
    }

    /// Set skipPolling from outside the actor.
    public func setSkipPolling(_ value: Bool) {
        skipPolling = value
    }

    /// Enable slow polling for radios that click with fast CAT commands (e.g. FT-891).
    public func setSlowPolling(_ value: Bool) {
        useSlowPolling = value
    }

    /// Set onRawFrame callback from outside the actor.
    public func setOnRawFrame(_ callback: (@Sendable (Data) -> Void)?) {
        onRawFrame = callback
    }

    /// Set codecTap from outside the actor.
    public func setCodecTap(_ callback: (@Sendable (Data) -> Void)?) {
        codecTap = callback
    }

    public func start() async throws {
        try await transport.connect()
        state.isConnected = true

        receiveTask = Task { [weak self] in
            guard let self else {
                return
            }
            await receiveLoop()
        }

        if !skipPolling {
            pollTask = Task { [weak self] in
                guard let self else {
                    return
                }
                await pollLoop()
            }
        }
    }

    public func stop() async {
        receiveTask?.cancel()
        receiveTask = nil
        pollTask?.cancel()
        pollTask = nil
        await transport.disconnect()
        state.isConnected = false
    }

    /// Cancel this session's receive + poll tasks WITHOUT disconnecting the
    /// transport. Use this when swapping in a fresh session that shares the
    /// same physical link (e.g. the CW Bridge after radio auto-detection).
    /// Without this, two sessions race to consume the bridge's single
    /// `receivedData` AsyncStream — every chunk goes to exactly one consumer,
    /// so each session's frame assembler sees a truncated byte stream and
    /// `decodeFrequency` returns garbled values from partial frames.
    public func cancelTasks() {
        receiveTask?.cancel()
        receiveTask = nil
        pollTask?.cancel()
        pollTask = nil
    }

    public func tuneToFrequency(_ freqMHz: Double) async -> Bool {
        let freqHz = UInt64((freqMHz * 1_000_000).rounded())
        var value = Data(count: 8)
        value.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: freqHz.littleEndian, as: UInt64.self)
        }
        return await sendVerified(field: 0x01, value: value) {
            await self.sendEncoded(self.protocolHandler.encodeSetFrequency(freqMHz))
        }
    }

    public func setMode(_ mode: String, universalModeRawValue: UInt8?) async -> Bool {
        let fallback: () async -> Bool = {
            await self.sendEncoded(self.protocolHandler.encodeSetMode(mode))
        }
        guard let modeValue = universalModeRawValue else {
            return await fallback()
        }
        return await sendVerified(field: 0x02, value: Data([modeValue]), fallback: fallback)
    }

    public func setPTT(_ on: Bool) async -> Bool {
        let result = await sendVerified(field: 0x03, value: Data([on ? 0x01 : 0x00])) {
            await self.sendEncoded(self.protocolHandler.encodeSetPTT(on))
        }
        if result {
            state.isTransmitting = on
        }
        return result
    }

    public func sendRaw(_ data: Data) async throws {
        try await transport.send(data)
    }

    /// Send `text` as CW through the radio's CAT keyer (e.g. CI-V `1A 02`,
    /// Kenwood/Elecraft `KY`, Yaesu `KY`). Returns true on transport success.
    /// Returns false when the protocol handler doesn't expose CAT keying.
    /// This is the "third path" used by callers that are not driving a CW
    /// Bridge or a WinKeyer — i.e. CAT over USB serial or CAT over TCP.
    public func sendCW(_ text: String) async -> Bool {
        guard let data = protocolHandler.encodeSendCW(text) else {
            return false
        }
        return await sendEncoded(data)
    }

    /// Best-effort CW abort via the radio's CAT handler. Falls back to PTT-off
    /// for handlers that don't have a dedicated abort command.
    public func abortCW() async -> Bool {
        guard let data = protocolHandler.encodeAbortCW() else {
            return false
        }
        return await sendEncoded(data)
    }

    public func setXIT(_ on: Bool) async -> Bool {
        await sendVerified(field: 0x04, value: Data([on ? 0x01 : 0x00])) {
            guard let data = self.protocolHandler.encodeSetXIT(on) else {
                return false
            }
            return await self.sendEncoded(data)
        }
    }

    public func setRIT(_ on: Bool) async -> Bool {
        // No protocol-level RIT-on encoder today; bridge-only field.
        await sendVerified(field: 0x05, value: Data([on ? 0x01 : 0x00])) { false }
    }

    public func setRITXITOffset(_ hz: Int) async -> Bool {
        let val = Int16(clamping: hz)
        var value = Data(count: 2)
        value.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: val.littleEndian, as: Int16.self)
        }
        return await sendVerified(field: 0x06, value: value) {
            guard let data = self.protocolHandler.encodeSetXITOffset(hz) else {
                return false
            }
            return await self.sendEncoded(data)
        }
    }

    public func clearRITXIT() async -> Bool {
        await sendVerified(field: 0x07, value: Data()) {
            guard let data = self.protocolHandler.encodeClearRITXIT() else {
                return false
            }
            return await self.sendEncoded(data)
        }
    }

    public func setPowerLevel(_ watts: UInt8) async -> Bool {
        // No protocol-level power encoder today; bridge-only field.
        let result = await sendVerified(field: 0x08, value: Data([watts])) { false }
        if result {
            state.powerLevel = watts
        }
        return result
    }

    // MARK: Internal

    /// Accessible to the `RadioSession+Query.swift` extension that hosts
    /// `sendQuery`. Reverting to `private` is fine if `sendQuery` moves back
    /// into this file.
    let transport: any RadioTransport
    var pollTask: Task<Void, Never>?

    func pollLoop() async {
        let transportInterval = await transport.recommendedPollInterval
        let interval = useSlowPolling ? max(transportInterval, .milliseconds(500)) : transportInterval
        let slowPoll = useSlowPolling || interval >= .milliseconds(500)

        // For slow transports (WiFi), alternate between commands each cycle
        // to avoid flooding the radio. One command per cycle at 1s intervals
        // instead of all commands at 200ms.
        var pollIndex = 0

        while !Task.isCancelled, state.isConnected {
            if slowPoll {
                // Send one command per cycle, rotating through available polls
                let cmd = pollCommand(at: pollIndex)
                if let cmd {
                    try? await transport.send(cmd)
                }
                pollIndex += 1
            } else {
                // Fast transport (BLE): send all commands each cycle
                if let cmd = protocolHandler.encodeReadFrequency() {
                    try? await transport.send(cmd)
                }
                if let cmd = protocolHandler.encodeReadMode() {
                    try? await transport.send(cmd)
                }
                if let cmd = protocolHandler.encodeReadXIT() {
                    try? await transport.send(cmd)
                }
                if let cmd = protocolHandler.encodeReadRIT() {
                    try? await transport.send(cmd)
                }
                if let cmd = protocolHandler.encodeReadRITXITOffset() {
                    try? await transport.send(cmd)
                }
                if let cmd = protocolHandler.encodeReadPowerLevel() {
                    try? await transport.send(cmd)
                }
                if let cmd = protocolHandler.encodeReadPTT() {
                    try? await transport.send(cmd)
                }
            }
            try? await Task.sleep(for: interval)
        }
    }

    // MARK: Private

    private let protocolHandler: any RadioProtocolHandler
    private let frameAssembler: FrameAssembler
    private var receiveTask: Task<Void, Never>?

    /// Send a verified set command via the bridge, pausing polling during the operation.
    /// Falls back to `fallback` when the transport reports the field as unsupported
    /// (default extension on RadioTransport returns 0x02 — true for any non-bridge
    /// transport such as Flex TCP, serial CAT, IcomWiFi, SCU-LAN10).
    private func sendVerified(
        field: UInt8,
        value: Data,
        fallback: () async -> Bool
    ) async -> Bool {
        // Pause polling to avoid RX contamination on the bridge
        let wasPolling = pollTask != nil
        pollTask?.cancel()
        pollTask = nil

        let result = await transport.sendSetVerify(field: field, value: value)

        // Resume polling if it was active
        if wasPolling, !skipPolling {
            pollTask = Task { [weak self] in
                guard let self else {
                    return
                }
                await pollLoop()
            }
        }

        if result == 0x00 { // CWBP_RESULT_OK
            return true
        }
        if result == 0x02 { // CWBP_RESULT_UNSUPPORTED
            return await fallback()
        }
        return false // CWBP_RESULT_FAIL
    }

    /// Encode-and-send shortcut for the non-bridge fallback path.
    private func sendEncoded(_ data: Data) async -> Bool {
        do {
            try await transport.send(data)
            return true
        } catch {
            return false
        }
    }

    private func receiveLoop() async {
        for await data in transport.receivedData {
            let frames = await frameAssembler.feed(data)
            for frame in frames {
                processFrame(frame)
                onRawFrame?(frame)
                codecTap?(frame)
            }
        }
        // Stream ended — transport disconnected (keepalive timeout, etc.)
        state.isConnected = false
    }

    private func processFrame(_ frame: Data) {
        if let freq = protocolHandler.decodeFrequency(from: frame) {
            state.frequency = freq
        }
        if let mode = protocolHandler.decodeMode(from: frame) {
            state.mode = mode
        }
        if let tx = protocolHandler.decodePTTState(from: frame) {
            state.isTransmitting = tx
        }
        if let xit = protocolHandler.decodeXITState(from: frame) {
            state.xitEnabled = xit
        }
        if let rit = protocolHandler.decodeRITState(from: frame) {
            state.ritEnabled = rit
        }
        if let offset = protocolHandler.decodeRITXITOffset(from: frame) {
            state.ritXitOffset = offset
        }
        if let power = protocolHandler.decodePowerLevel(from: frame) {
            state.powerLevel = power
        }
    }

    /// Returns the poll command for the given index. Frequency is polled on
    /// every even cycle for responsive dial tracking; the remaining parameters
    /// (mode → XIT → RIT → offset → power) rotate on the odd cycles in between.
    /// Skips nil commands.
    private func pollCommand(at index: Int) -> Data? {
        let freq = protocolHandler.encodeReadFrequency()
        let others = [
            protocolHandler.encodeReadMode(),
            protocolHandler.encodeReadXIT(),
            protocolHandler.encodeReadRIT(),
            protocolHandler.encodeReadRITXITOffset(),
            protocolHandler.encodeReadPowerLevel(),
            protocolHandler.encodeReadPTT(),
        ].compactMap { $0 }

        // Even cycle → frequency (~1 s at the 500 ms slow-poll rate); odd
        // cycle → next rotating parameter.
        if index.isMultiple(of: 2), let freq {
            return freq
        }
        guard !others.isEmpty else {
            return freq
        }
        return others[(index / 2) % others.count]
    }
}
