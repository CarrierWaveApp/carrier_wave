import CarrierWaveCore
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RemoteOpConnection")

// MARK: - RemoteOpConnection

//
// Owns the lifecycle of a single iOS client. Drives any `RemoteOpTransport`
// (LAN TCP or MultipeerConnectivity), handles the hello/pair handshake,
// the per-connection subscription registry, and the dispatch of inbound
// commands. State here is per-client only — global state lives in
// RemoteOpService.

actor RemoteOpConnection {
    // MARK: Lifecycle

    init(
        id: UUID,
        transport: RemoteOpTransport,
        service: RemoteOpService
    ) {
        self.id = id
        self.transport = transport
        self.service = service
    }

    // MARK: Internal

    nonisolated let id: UUID

    // MARK: - Private state

    weak var service: RemoteOpService?
    var authenticated = false

    /// Begin the receive loop. The transport is expected to be unstarted —
    /// this method starts it, then drives the incoming stream until close.
    func start() async {
        await transport.start()
        await receiveLoop()
    }

    /// Cancels the underlying transport and drains state.
    func cancel() {
        guard !cancelled else {
            return
        }
        cancelled = true
        Task { [transport] in
            await transport.cancel()
        }
    }

    // MARK: - Inbound frame dispatch

    nonisolated func publishIfSubscribed(_ frame: RemoteOpFrame, topic: RemoteOpTopic) async {
        await publish(frame, topic: topic)
    }

    func sendFrame(_ frame: RemoteOpFrame) async {
        let data: Data
        do {
            data = try RemoteOpFraming.encode(frame)
        } catch {
            logger.error("Encode failed: \(error.localizedDescription)")
            return
        }
        do {
            try await transport.send(data)
        } catch {
            logger.warning("Send failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    private let transport: RemoteOpTransport

    private var cancelled = false
    private var deviceID: UUID?
    private var subscriptions: Set<RemoteOpTopic> = []

    private func publish(_ frame: RemoteOpFrame, topic: RemoteOpTopic) async {
        guard authenticated, subscriptions.contains(topic) else {
            return
        }
        await sendFrame(frame)
    }

    // MARK: - Receive loop

    private func receiveLoop() async {
        for await frameData in await transport.incoming() {
            if cancelled {
                break
            }
            await handleFrameData(frameData)
        }
        await closed()
    }

    private func handleFrameData(_ data: Data) async {
        let frame: RemoteOpFrame
        do {
            frame = try RemoteOpFraming.decode(data)
        } catch {
            await sendFrame(.errorFrame(.init(
                code: .invalidPayload,
                message: "decode failed: \(error.localizedDescription)"
            )))
            return
        }
        await dispatch(frame)
    }

    private func dispatch(_ frame: RemoteOpFrame) async {
        switch frame {
        case let .hello(hello):
            await handleHello(hello)
        case let .pair(pair):
            await handlePair(pair)
        case let .subscribe(sub):
            await handleSubscribe(sub)
        case let .unsubscribe(unsub):
            subscriptions.remove(unsub.topic)
        case let .commandTune(cmd):
            await handleTune(cmd)
        case let .commandSetQuerySelection(cmd):
            await handleSetQuerySelection(cmd)
        case let .commandSendCW(cmd):
            await handleSendCW(cmd)
        case let .commandStopCW(cmd):
            await handleStopCW(cmd)
        case let .commandSetCWSpeed(cmd):
            await handleSetCWSpeed(cmd)
        case let .commandPlayCWSlot(cmd):
            await handlePlayCWSlot(cmd)
        case let .commandSetCWSlot(cmd):
            await handleSetCWSlot(cmd)
        case let .commandSetActiveSession(cmd):
            await handleSetActiveSession(cmd)
        case let .ping(ping):
            await sendFrame(.pong(.init(nonce: ping.nonce)))
        default:
            // server doesn't react to other inbound frame kinds in v1
            break
        }
    }

    // MARK: - Handlers

    private func handleHello(_ hello: Hello) async {
        guard hello.protocolVersion == RemoteOp.protocolVersion else {
            await sendFrame(.errorFrame(.init(
                code: .versionMismatch,
                message: "expected v\(RemoteOp.protocolVersion), got v\(hello.protocolVersion)"
            )))
            cancel()
            return
        }

        // Token-based reconnect path.
        if let token = hello.token, let device = await service?.deviceForToken(token) {
            deviceID = device.id
            authenticated = true
            await service?.setDeviceActive(device.id, active: true, connection: self)
            await sendHelloAck(authenticated: true)
            await sendCurrentRadioState()
            return
        }

        // Unauthenticated greeting; client will follow up with `pair`.
        await sendHelloAck(authenticated: false)
    }

    private func handlePair(_ pair: Pair) async {
        guard let service else {
            return
        }
        let device = await MainActor.run {
            service.consumePairing(code: pair.code, requestedName: pair.deviceName)
        }
        guard let device else {
            await sendFrame(.errorFrame(.init(
                code: .pairingRefused,
                message: "incorrect pairing code"
            )))
            return
        }
        deviceID = device.id
        authenticated = true
        await MainActor.run {
            service.setDeviceActive(device.id, active: true, connection: self)
        }
        await sendFrame(.paired(.init(token: device.token, deviceID: device.id)))
        await sendCurrentRadioState()
    }

    private func handleSubscribe(_ sub: Subscribe) async {
        guard authenticated else {
            await sendFrame(.errorFrame(.init(
                code: .notAuthenticated,
                message: "subscribe before pairing/hello-with-token"
            )))
            return
        }
        subscriptions.insert(sub.topic)

        // Send an immediate snapshot so the client has something to render.
        switch sub.topic {
        case .radioState:
            await sendCurrentRadioState()
        case .spotsFeed:
            await sendSpotsBackfill(filter: sub.filter)
        case .queriesList:
            await sendCurrentQueriesList()
        case .querySelection:
            await sendCurrentQuerySelection()
        case .cwKeyer:
            await sendCurrentCWStatus()
        case .cwSlots:
            await sendCurrentCWSlots()
        case .activeSession:
            await sendCurrentActiveSession()
        case .waterfall:
            // No backfill — client wants the live stream. The first frame
            // will arrive on the next producer tick. Sending a cleared
            // event up front lets the client render an empty panel.
            await sendCurrentWaterfallSnapshot()
        case .audio:
            // Audio is gated on the broadcaster having a format. If a
            // radio's connected, send the format snapshot now so the
            // client can spin up its player; otherwise stay silent and
            // the format event will go out when the radio comes online.
            await sendCurrentAudioFormatIfAvailable()
        case .radioMeters:
            break // periodic publisher will emit
        }
    }

    private func handleSetQuerySelection(_ cmd: SetQuerySelectionCommand) async {
        guard await requireAuth(action: "set-query"), let service else {
            return
        }
        let ack = await service.handleSetQuerySelection(cmd)
        await sendFrame(.ack(ack))
    }

    private func sendCurrentQueriesList() async {
        guard let service else {
            return
        }
        let queries = await service.currentQueryListSnapshot()
        await sendFrame(.eventQueriesList(.init(queries: queries)))
    }

    private func sendCurrentQuerySelection() async {
        guard let service else {
            return
        }
        let snapshot = await MainActor.run { service.currentQuerySelectionSnapshot() }
        await sendFrame(.eventQuerySelection(snapshot))
    }

    private func handleTune(_ cmd: TuneCommand) async {
        guard await requireAuth(action: "tune"), let service else {
            return
        }
        let ack = await service.handleTune(cmd)
        await sendFrame(.ack(ack))
    }

    // MARK: - Snapshots

    private func sendCurrentRadioState() async {
        guard let service else {
            return
        }
        let snapshot = await MainActor.run { service.currentRadioStateSnapshot() }
        if let snapshot {
            await sendFrame(.eventRadioState(snapshot))
        }
    }

    private func sendSpotsBackfill(filter: SubscribeFilter?) async {
        guard let service else {
            return
        }
        let spots = await MainActor.run { service.currentSpotsSnapshot(filter: filter) }
        for spot in spots {
            await sendFrame(.eventSpot(.init(spot: spot)))
        }
    }

    // MARK: - Send

    private func sendHelloAck(authenticated: Bool) async {
        let ack = HelloAck(
            serverName: Host.current().localizedName ?? "CW Sweep",
            serverPlatform: "macOS",
            serverVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            authenticated: authenticated,
            serverTimeUTC: Date()
        )
        await sendFrame(.helloAck(ack))
    }

    // MARK: - State changes

    private func closed() async {
        let captured = deviceID
        let connID = id
        await MainActor.run { [weak service] in
            service?.connectionDidClose(id: connID, deviceID: captured)
        }
    }
}
