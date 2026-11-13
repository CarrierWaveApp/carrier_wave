import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - BridgeProtocol

/// CW Bridge Protocol (CWBP) layer over BLE NUS.
///
/// Wraps `BLERadioTransport` and conforms to `RadioTransport`, so `RadioSession`
/// sees only raw CAT bytes. CWBP framing, handshake, and metadata are handled
/// transparently.
actor BridgeProtocol {
    // MARK: Lifecycle

    init(transport: BLERadioTransport) {
        rawTransport = transport

        var catCont: AsyncStream<Data>.Continuation?
        receivedDataStream = AsyncStream<Data> { continuation in
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
    let receivedDataStream: AsyncStream<Data>

    /// Stream of bridge metadata events (handshake, status, detection).
    let bridgeEvents: AsyncStream<BridgeEvent>

    var mode: Mode = .handshaking

    /// Firmware version string set after handshake.
    var firmwareVersion: String?

    /// Bridge capability flags
    var capabilities: UInt8 = 0

    nonisolated var hasDirectWriter: Bool {
        rawTransport.directWriter != nil
    }

    // MARK: - Handshake

    /// Start the protocol: send handshake, begin processing incoming data.
    func start() {
        receiveTask = Task { await processIncomingData() }

        let req = BridgeFrame.buildHandshakeReq()
        handshakeTask = Task {
            var sent = false
            for attempt in 0 ..< 3 {
                do {
                    if attempt > 0 {
                        try await Task.sleep(for: .milliseconds(200))
                    }
                    try await rawTransport.send(req)
                    sent = true
                    break
                } catch {
                    // BLE write failed — retry
                }
            }

            guard sent else {
                eventContinuation?.yield(.bridgeError("Handshake send failed after 3 attempts"))
                return
            }

            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            if mode == .handshaking {
                eventContinuation?.yield(.bridgeError("Handshake timeout — no response from bridge"))
            }
        }
    }

    func cancelHandshake() {
        receiveTask?.cancel()
        receiveTask = nil
        handshakeTask?.cancel()
        handshakeTask = nil
        mode = .handshaking
    }

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
    /// periodic self-heal — the firmware's one-shot status push at
    /// handshake time is racy if the event stream isn't draining yet.
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

    func sendCW(_ text: String) async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWSend(text)
        try await rawTransport.send(frame)
    }

    func stopCW() async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWStop()
        try await rawTransport.send(frame)
    }

    func setCWSpeed(wpm: UInt8) async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWSpeed(wpm: wpm)
        try await rawTransport.send(frame)
    }

    func playCWSlot(_ slot: UInt8, context: [String: String] = [:]) async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWSlotPlay(slot: slot, context: context)
        try await rawTransport.send(frame)
    }

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

    nonisolated func stopCWImmediate() {
        let frame = BridgeFrame.buildCWStop()
        rawTransport.directWriter?.writeData(frame)
    }

    nonisolated func sendCWImmediate(_ text: String) {
        let frame = BridgeFrame.buildCWSend(text)
        rawTransport.directWriter?.writeData(frame)
    }

    func requestCWStatus() async throws {
        guard mode == .framed else {
            return
        }
        let frame = BridgeFrame.buildCWStatusReq()
        try await rawTransport.send(frame)
    }

    // MARK: Private

    nonisolated private let rawTransport: BLERadioTransport
    private var catContinuation: AsyncStream<Data>.Continuation?
    private var eventContinuation: AsyncStream<BridgeEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?
    private var pendingVerifyContinuation: CheckedContinuation<UInt8, Never>?
    private var verifyTimeoutTask: Task<Void, Never>?

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
        guard let msg = BridgeFrame.parse(data) else {
            catContinuation?.yield(data)
            return
        }

        if case .handshakeRsp = msg.msg {
            handshakeTask?.cancel()
            handshakeTask = nil

            if let event = BridgeFrame.event(from: msg),
               case let .handshakeComplete(fwVersion, caps) = event
            {
                firmwareVersion = fwVersion
                capabilities = caps
                mode = .framed
                eventContinuation?.yield(event)
            } else {
                eventContinuation?.yield(.bridgeError("Malformed handshake response"))
            }
        } else {
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

        if let catPayload = BridgeFrame.catPayload(from: msg) {
            catContinuation?.yield(catPayload)
            return
        }

        if case let .setResult(result) = msg.msg {
            handleSetResult(result)
            return
        }

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
    nonisolated var receivedData: AsyncStream<Data> {
        receivedDataStream
    }

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
            try await rawTransport.send(data)
        }
    }

    func sendSetVerify(field: UInt8, value: Data) async -> UInt8 {
        guard mode == .framed else {
            return BridgeFrame.SetResultCode.fail.rawValue
        }

        pendingVerifyContinuation?.resume(returning: BridgeFrame.SetResultCode.fail.rawValue)
        pendingVerifyContinuation = nil
        verifyTimeoutTask?.cancel()

        guard let fieldEnum = Cwbp_SetVerifyField(rawValue: Int(field)) else {
            return BridgeFrame.SetResultCode.unsupported.rawValue
        }
        let frame = BridgeFrame.buildSetVerify(field: fieldEnum, value: value)
        do {
            try await rawTransport.send(frame)
        } catch {
            return BridgeFrame.SetResultCode.fail.rawValue
        }

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
