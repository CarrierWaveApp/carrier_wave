import CarrierWaveData
import UIKit

// MARK: - BridgeProtocol

/// CW Bridge Protocol (CWBP) layer over BLE NUS.
///
/// Wraps `BLERadioTransport` and conforms to `RadioTransport`, so
/// `RadioSession` sees only raw CAT bytes. CWBP framing, handshake,
/// and metadata are handled transparently.
actor BridgeProtocol {
    // MARK: Lifecycle

    init(transport: BLERadioTransport) {
        rawTransport = transport

        var catCont: AsyncStream<Data>.Continuation?
        receivedData = AsyncStream<Data> { continuation in
            catCont = continuation
        }
        catContinuation = catCont

        var evtCont: AsyncStream<BridgeEvent>.Continuation?
        bridgeEvents = AsyncStream<BridgeEvent> { continuation in
            evtCont = continuation
        }
        eventContinuation = evtCont
    }

    // MARK: Internal

    enum Mode {
        case handshaking
        case framed
    }

    /// Stream of raw CAT data (framing stripped). Feed this to RadioSession.
    let receivedData: AsyncStream<Data>

    /// Stream of bridge metadata events (handshake, status, detection).
    let bridgeEvents: AsyncStream<BridgeEvent>

    var mode: Mode = .handshaking

    /// Firmware version string (e.g. "1.0.0"), set after handshake.
    var firmwareVersion: String?

    /// Bridge capability flags
    var capabilities: UInt8 = 0

    // Accessed by the satellite command extension (BridgeProtocol+Satellite).
    nonisolated let rawTransport: BLERadioTransport
    var pendingSatAckContinuation: CheckedContinuation<Cwbp_SatScheduleAck?, Never>?
    var satAckTimeoutTask: Task<Void, Never>?

    // MARK: - Immediate CW Commands (bypass actor serialization)

    /// Whether the direct BLE write path is available.
    nonisolated var hasDirectWriter: Bool {
        rawTransport.directWriter != nil
    }

    // MARK: - Handshake

    /// Start the protocol: send handshake, begin processing incoming data.
    /// Call this after BLE transport connects and subscribes.
    func start() {
        receiveTask = Task { await processIncomingData() }

        // Send handshake request with retries. The BLE write can fail
        // if called immediately after subscription before the link is
        // fully ready.
        let req = BridgeFrame.buildHandshakeReq()
        let reqSize = req.count
        handshakeTask = Task {
            var sent = false
            var lastError: String?
            for attempt in 0 ..< 3 {
                do {
                    if attempt > 0 {
                        try await Task.sleep(for: .milliseconds(200))
                    }
                    try await rawTransport.send(req)
                    sent = true
                    let n = attempt + 1
                    Task { @MainActor in
                        RadioService.shared.addLog(
                            .info,
                            "Bridge: handshake TX sent (\(reqSize) bytes, attempt \(n))"
                        )
                    }
                    break
                } catch {
                    lastError = error.localizedDescription
                }
            }

            guard sent else {
                let err = lastError ?? "unknown"
                Task { @MainActor in
                    RadioService.shared.addLog(.error, "Bridge: handshake TX failed — \(err)")
                }
                eventContinuation?.yield(.bridgeError("Handshake send failed after 3 attempts"))
                return
            }

            // Wait for handshake response (up to 2 seconds)
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            if mode == .handshaking {
                eventContinuation?.yield(.bridgeError("Handshake timeout — no response from bridge"))
            }
        }
    }

    /// Cancel in-flight handshake and receive loop, reset mode so start() can be
    /// called again. Unlike stop(), this preserves the event/data streams for reuse
    /// after reconnect.
    func cancelHandshake() {
        receiveTask?.cancel()
        receiveTask = nil
        handshakeTask?.cancel()
        handshakeTask = nil
        mode = .handshaking
    }

    /// Stop processing and clean up.
    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        handshakeTask?.cancel()
        handshakeTask = nil
        catContinuation?.finish()
        eventContinuation?.finish()
    }

    /// Request the bridge to re-detect the radio.
    func requestDetection() async throws {
        let frame = BridgeFrame.buildRequestDetect()
        try await rawTransport.send(frame)
    }

    /// Ask the bridge to re-push its current state (USB connect, detected
    /// radio, jack/battery). Used to interrogate after handshake and as a
    /// periodic self-heal — relying on the firmware's one-shot status push
    /// at handshake time is racy if the iOS event stream isn't draining yet.
    func requestStatus() async throws {
        let frame = BridgeFrame.buildStatusReq()
        try await rawTransport.send(frame)
    }

    /// Set the bridge baud rate manually.
    func setBaud(_ baudRate: UInt32) async throws {
        let frame = BridgeFrame.buildSetBaud(baudRate)
        try await rawTransport.send(frame)
    }

    // MARK: - CW Keyer Commands

    /// Send CW text via the bridge keyer.
    func sendCW(_ text: String) async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWSend(text)
        try await rawTransport.send(frame)
    }

    /// Abort any active CW transmission.
    func stopCW() async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWStop()
        try await rawTransport.send(frame)
    }

    /// Set CW keyer speed in WPM.
    func setCWSpeed(wpm: UInt8) async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWSpeed(wpm: wpm)
        try await rawTransport.send(frame)
    }

    /// Play a stored CW memory slot with optional template context.
    func playCWSlot(_ slot: UInt8, context: [String: String] = [:]) async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWSlotPlay(slot: slot, context: context)
        try await rawTransport.send(frame)
    }

    /// Store text in a CW memory slot on the bridge.
    func setCWSlot(_ slot: UInt8, text: String) async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWSlotSet(slot: slot, text: text)
        try await rawTransport.send(frame)
    }

    /// Play a CW slot immediately, bypassing actor hops for minimum latency.
    nonisolated func playCWSlotImmediate(_ slot: UInt8, context: [String: String] = [:]) {
        let frame = BridgeFrame.buildCWSlotPlay(slot: slot, context: context)
        rawTransport.directWriter?.writeData(frame)
    }

    /// Stop CW immediately, bypassing actor hops.
    nonisolated func stopCWImmediate() {
        let frame = BridgeFrame.buildCWStop()
        rawTransport.directWriter?.writeData(frame)
    }

    /// Send CW text immediately, bypassing actor hops.
    nonisolated func sendCWImmediate(_ text: String) {
        let frame = BridgeFrame.buildCWSend(text)
        rawTransport.directWriter?.writeData(frame)
    }

    /// Request CW engine status from the bridge.
    func requestCWStatus() async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWStatusReq()
        try await rawTransport.send(frame)
    }

    // MARK: Private

    private var catContinuation: AsyncStream<Data>.Continuation?
    private var eventContinuation: AsyncStream<BridgeEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?
    private var pendingVerifyContinuation: CheckedContinuation<UInt8, Never>?
    private var verifyTimeoutTask: Task<Void, Never>?

    /// Process all incoming BLE data, dispatching by mode.
    /// Gets a fresh data stream each time — previous streams are single-use.
    private func processIncomingData() async {
        let stream = await rawTransport.makeDataStream()
        for await data in stream {
            guard !Task.isCancelled else {
                break
            }
            handleIncomingData(data)
        }
    }

    private func handleIncomingData(_ data: Data) {
        switch mode {
        case .handshaking:
            handleHandshakingData(data)
        case .framed:
            handleFramedData(data)
        }
    }

    private func handleHandshakingData(_ data: Data) {
        let byteCount = data.count
        Task { @MainActor in
            RadioService.shared.addLog(.info, "Bridge: handshake RX \(byteCount) bytes")
        }
        guard let msg = BridgeFrame.parse(data) else {
            // Not valid protobuf — could be leftover raw data.
            Task { @MainActor in
                RadioService.shared.addLog(.error, "Bridge: handshake RX failed to parse")
            }
            catContinuation?.yield(data)
            return
        }

        let msgType = msg.msg.map { String(describing: $0).prefix(40) } ?? "<empty>"
        Task { @MainActor in
            RadioService.shared.addLog(.info, "Bridge: handshake RX msg=\(msgType)")
        }

        if case .handshakeRsp = msg.msg {
            handshakeTask?.cancel()
            handshakeTask = nil

            if let event = BridgeFrame.event(from: msg),
               case let .handshakeComplete(fwVersion, caps) = event
            {
                let capsHex = String(caps, radix: 16)
                Task { @MainActor in
                    RadioService.shared.addLog(.info, "Bridge: handshakeComplete fw=\(fwVersion) caps=0x\(capsHex)")
                }
                firmwareVersion = fwVersion
                capabilities = caps
                mode = .framed
                eventContinuation?.yield(event)
            } else {
                eventContinuation?.yield(.bridgeError("Malformed handshake response"))
            }
        } else {
            // Got a non-handshake message during handshake —
            // bridge is already in framed mode (reconnect scenario)
            Task { @MainActor in
                RadioService.shared.addLog(.info, "Bridge: non-handshake during handshaking — switching to framed")
            }
            handshakeTask?.cancel()
            handshakeTask = nil
            mode = .framed
            handleFramedData(data)
        }
    }

    private func handleFramedData(_ data: Data) {
        guard let msg = BridgeFrame.parse(data) else {
            catContinuation?.yield(data)
            return
        }

        // Extract CAT data directly
        if let catPayload = BridgeFrame.catPayload(from: msg) {
            catContinuation?.yield(catPayload)
            return
        }

        // Handle set-verify results specially (pending continuation)
        if case let .setResult(result) = msg.msg {
            handleSetResult(result)
            return
        }

        // Resolve a pending sat-upload ack wait; the event still flows to
        // the generic stream below for logging.
        if case let .satAck(ack) = msg.msg {
            pendingSatAckContinuation?.resume(returning: ack)
            pendingSatAckContinuation = nil
            satAckTimeoutTask?.cancel()
            satAckTimeoutTask = nil
        }

        // All other messages → BridgeEvent
        if let event = BridgeFrame.event(from: msg) {
            eventContinuation?.yield(event)
        }
    }

    private func handleSetResult(_ result: Cwbp_SetResult) {
        guard let code = BridgeFrame.SetResultCode(rawValue: UInt8(result.result.rawValue)) else {
            return
        }
        eventContinuation?.yield(.setVerifyResult(result: code))
        pendingVerifyContinuation?.resume(returning: code.rawValue)
        pendingVerifyContinuation = nil
        verifyTimeoutTask?.cancel()
        verifyTimeoutTask = nil
    }
}

// MARK: RadioTransport

extension BridgeProtocol: RadioTransport {
    var isConnected: Bool {
        get async {
            await rawTransport.isConnected
        }
    }

    func connect() async throws {
        try await rawTransport.connect()
    }

    func disconnect() async {
        stop()
        await rawTransport.disconnect()
    }

    func send(_ data: Data) async throws {
        switch mode {
        case .framed:
            let frame = BridgeFrame.buildCatData(data)
            try await rawTransport.send(frame)
        case .handshaking:
            // During handshake, send raw — session may start polling
            // before handshake completes
            try await rawTransport.send(data)
        }
    }

    func sendSetVerify(field: UInt8, value: Data) async -> UInt8 {
        guard mode == .framed else {
            return BridgeFrame.SetResultCode.fail.rawValue
        }

        // Cancel any stale pending verify
        pendingVerifyContinuation?.resume(returning: BridgeFrame.SetResultCode.fail.rawValue)
        pendingVerifyContinuation = nil
        verifyTimeoutTask?.cancel()

        // Build and send the frame
        guard let fieldEnum = Cwbp_SetVerifyField(rawValue: Int(field)) else {
            return BridgeFrame.SetResultCode.unsupported.rawValue
        }
        let frame = BridgeFrame.buildSetVerify(field: fieldEnum, value: value)
        do {
            try await rawTransport.send(frame)
        } catch {
            return BridgeFrame.SetResultCode.fail.rawValue
        }

        // Await result with safety timeout
        return await withCheckedContinuation { continuation in
            pendingVerifyContinuation = continuation
            verifyTimeoutTask = Task {
                try? await Task.sleep(for: .milliseconds(2_000))
                guard !Task.isCancelled else {
                    return
                }
                pendingVerifyContinuation?.resume(returning: BridgeFrame.SetResultCode.fail.rawValue)
                pendingVerifyContinuation = nil
            }
        }
    }
}
