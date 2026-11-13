import CarrierWaveCore
import UIKit

// MARK: - RemoteSweepClient

//
// Owns one transport (LAN TCP or MultipeerConnectivity) to a CW Sweep
// server. Handles the hello/pair/subscribe protocol and surfaces inbound
// events as a typed callback. The coordinator owns the lifecycle
// (connect/disconnect) and decides what state to render.
//
// This actor knows nothing about UI — it just speaks the protocol.

actor RemoteSweepClient {
    // MARK: Lifecycle

    init(
        transport: RemoteOpTransport,
        deviceName: String,
        existingToken: String?,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.transport = transport
        self.deviceName = deviceName
        token = existingToken
        self.onEvent = onEvent
    }

    // MARK: Internal

    // MARK: - Public types

    enum Event {
        case status(Status)
        case helloAck(HelloAck)
        case paired(Paired)
        case radioState(RadioStateEvent)
        case spot(RemoteSpot)
        case queriesList([RemoteSavedQuery])
        case querySelection(RemoteFilterMode)
        case cwStatus(CWStatusEvent)
        case cwSlots([RemoteCWSlot])
        case activeSession(ActiveSessionEvent)
        case waterfallLine(WaterfallLineEvent)
        case waterfallCleared(WaterfallClearedEvent)
        case audioFormat(AudioFormatEvent)
        case audioFrame(AudioFrameEvent)
        case error(ErrorFrame)
    }

    enum Status {
        case disconnected
        case connecting
        case authenticating
        case awaitingPairing
        case connected
        case failed(String)
    }

    enum ClientError: Error {
        case notConnected
        case timedOut
        case pairingRefused
        case versionMismatch
        case other(String)
    }

    /// Establish the transport and start the receive loop. Returns once the
    /// transport is kicked off — the receive loop runs in a detached task so
    /// the coordinator can carry on with UI flow.
    func connect() async {
        guard !started else {
            return
        }
        started = true
        emit(.status(.connecting))
        await transport.start()
        await sendInitialHello()
        Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    /// Disconnect cleanly. Idempotent.
    func disconnect() async {
        cancelled = true
        ackContinuations.values.forEach { $0.resume(throwing: ClientError.notConnected) }
        ackContinuations.removeAll()
        await transport.cancel()
        emit(.status(.disconnected))
    }

    /// Submit a pairing code. Resolves once the server replies with `paired` or `error`.
    @discardableResult
    func submitPairing(code: String) async throws -> Paired {
        guard authenticationState == .awaitingPairing else {
            throw ClientError.other("not in pairing state")
        }
        let frame = RemoteOpFrame.pair(.init(code: code, deviceName: deviceName))
        try await sendFrame(frame)
        return try await withCheckedThrowingContinuation { continuation in
            pairingContinuation = continuation
        }
    }

    /// Subscribe to a topic. v1 doesn't require ack; the server will start pushing.
    func subscribe(_ topic: RemoteOpTopic, filter: SubscribeFilter? = nil) async {
        try? await sendFrame(.subscribe(.init(topic: topic, filter: filter)))
    }

    /// Unsubscribe from a topic so the server stops broadcasting events the
    /// client doesn't currently care about.
    func unsubscribe(_ topic: RemoteOpTopic) async {
        try? await sendFrame(.unsubscribe(.init(topic: topic)))
    }

    /// Send a tune command. Returns the server's ack on success.
    func sendTune(freqHz: UInt64, mode: String?) async throws -> Ack {
        let id = UUID()
        let frame = RemoteOpFrame.commandTune(.init(requestID: id, freqHz: freqHz, mode: mode))
        try await sendFrame(frame)
        return try await awaitAck(for: id)
    }

    /// Ask the server to re-span the waterfall stream (k3fall extension).
    func setWaterfallView(spanHz: UInt64?) async throws -> Ack {
        let id = UUID()
        let frame = RemoteOpFrame.commandSetWaterfallView(.init(requestID: id, spanHz: spanHz))
        try await sendFrame(frame)
        return try await awaitAck(for: id)
    }

    /// Tell Sweep to switch the band-scope filter to widgets or a saved
    /// query. Returns the server's ack.
    func setQuerySelection(mode: RemoteFilterMode) async throws -> Ack {
        let id = UUID()
        let frame = RemoteOpFrame.commandSetQuerySelection(.init(requestID: id, mode: mode))
        try await sendFrame(frame)
        return try await awaitAck(for: id)
    }

    /// Push the locally-active LoggingSession over to Sweep so it can
    /// adopt the same session without waiting for CloudKit. The server
    /// applies via the same most-recent-startedAt rule used everywhere
    /// else, so passing a stale snapshot is harmless.
    @discardableResult
    func setActiveSession(_ session: RemoteSessionState) async throws -> Ack {
        let id = UUID()
        let frame = RemoteOpFrame.commandSetActiveSession(
            .init(requestID: id, session: session)
        )
        try await sendFrame(frame)
        return try await awaitAck(for: id)
    }

    func awaitAck(for id: UUID) async throws -> Ack {
        try await withCheckedThrowingContinuation { continuation in
            ackContinuations[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                await self?.timeoutAck(id: id)
            }
        }
    }

    // MARK: - Send

    func sendFrame(_ frame: RemoteOpFrame) async throws {
        let data: Data
        do {
            data = try RemoteOpFraming.encode(frame)
        } catch {
            throw ClientError.other("encode failed: \(error.localizedDescription)")
        }
        do {
            try await transport.send(data)
        } catch {
            // Likely-dead socket; cancel so the receive loop's stream
            // terminates and the coordinator can decide whether to reconnect.
            await transport.cancel()
            throw ClientError.other(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    func emit(_ event: Event) {
        onEvent(event)
    }

    // MARK: Private

    private enum AuthenticationState {
        case idle
        case awaitingHelloAck
        case awaitingPairing
        case authenticated
    }

    // MARK: - Private state

    private let transport: RemoteOpTransport
    private let deviceName: String
    private let onEvent: @Sendable (Event) -> Void

    private var token: String?
    private var started = false
    private var cancelled = false
    private var authenticationState: AuthenticationState = .idle
    private var pairingContinuation: CheckedContinuation<Paired, Error>?
    private var ackContinuations: [UUID: CheckedContinuation<Ack, Error>] = [:]

    private func sendInitialHello() async {
        authenticationState = .awaitingHelloAck
        emit(.status(.authenticating))
        let hello = RemoteOpFrame.hello(.init(
            clientName: deviceName,
            clientPlatform: "iOS",
            token: token
        ))
        try? await sendFrame(hello)
    }

    // MARK: - Receive

    private func receiveLoop() async {
        for await frameData in await transport.incoming() {
            if cancelled {
                break
            }
            await handleFrameData(frameData)
        }
        if !cancelled {
            emit(.status(.disconnected))
        }
    }

    private func handleFrameData(_ data: Data) async {
        let frame: RemoteOpFrame
        do {
            frame = try RemoteOpFraming.decode(data)
        } catch {
            emit(.error(.init(code: .invalidPayload, message: "decode: \(error.localizedDescription)")))
            return
        }
        await dispatch(frame)
    }

    private func dispatch(_ frame: RemoteOpFrame) async {
        if dispatchSyncEvent(frame) {
            return
        }
        await dispatchAsyncFrame(frame)
    }

    /// Handle every event-style frame that just emits a typed callback —
    /// these are pure synchronous fan-out work, isolated here so the
    /// outer `dispatch` can stay simple and the async-handling cases
    /// stay easy to spot.
    private func dispatchSyncEvent(_ frame: RemoteOpFrame) -> Bool {
        switch frame {
        case let .eventRadioState(event): emit(.radioState(event))
        case let .eventSpot(event): emit(.spot(event.spot))
        case let .eventQueriesList(event): emit(.queriesList(event.queries))
        case let .eventQuerySelection(event): emit(.querySelection(event.mode))
        case let .eventCWStatus(event): emit(.cwStatus(event))
        case let .eventCWSlots(event): emit(.cwSlots(event.slots))
        case let .eventActiveSession(event): emit(.activeSession(event))
        case let .eventWaterfallLine(event): emit(.waterfallLine(event))
        case let .eventWaterfallCleared(event): emit(.waterfallCleared(event))
        case let .eventAudioFormat(event): emit(.audioFormat(event))
        case let .eventAudioFrame(event): emit(.audioFrame(event))
        case let .ack(ack): handleAck(ack)
        case let .errorFrame(err): handleError(err)
        default: return false
        }
        return true
    }

    private func dispatchAsyncFrame(_ frame: RemoteOpFrame) async {
        switch frame {
        case let .helloAck(ack):
            await handleHelloAck(ack)
        case let .paired(paired):
            await handlePaired(paired)
        case let .ping(ping):
            try? await sendFrame(.pong(.init(nonce: ping.nonce)))
        default:
            break
        }
    }
}

// MARK: - Hello / pair / ack / error

extension RemoteSweepClient {
    private func handleHelloAck(_ ack: HelloAck) async {
        emit(.helloAck(ack))
        if ack.authenticated {
            authenticationState = .authenticated
            emit(.status(.connected))
        } else {
            authenticationState = .awaitingPairing
            emit(.status(.awaitingPairing))
        }
    }

    private func handlePaired(_ paired: Paired) async {
        token = paired.token
        authenticationState = .authenticated
        emit(.paired(paired))
        emit(.status(.connected))
        if let pairingContinuation {
            pairingContinuation.resume(returning: paired)
            self.pairingContinuation = nil
        }
    }

    private func handleAck(_ ack: Ack) {
        guard let continuation = ackContinuations.removeValue(forKey: ack.requestID) else {
            return
        }
        continuation.resume(returning: ack)
    }

    private func handleError(_ err: ErrorFrame) {
        emit(.error(err))
        if err.code == .pairingRefused, let pairingContinuation {
            pairingContinuation.resume(throwing: ClientError.pairingRefused)
            self.pairingContinuation = nil
        } else if err.code == .versionMismatch, let pairingContinuation {
            pairingContinuation.resume(throwing: ClientError.versionMismatch)
            self.pairingContinuation = nil
        }
        if let id = err.requestID, let continuation = ackContinuations.removeValue(forKey: id) {
            continuation.resume(throwing: ClientError.other(err.message))
        }
    }

    func timeoutAck(id: UUID) {
        guard let continuation = ackContinuations.removeValue(forKey: id) else {
            return
        }
        continuation.resume(throwing: ClientError.timedOut)
    }
}
