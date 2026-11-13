// S.A.T. socket listener
//
// Actor owning the NWListener (UDP or TCP) that receives ADIF records pushed
// by a CSN Technologies S.A.T. tracker. Socket work stays here; parsing and
// persistence happen on the main actor in `SatLogListenerService`.

import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "SatLogListener")

// MARK: - SatLogTransport

enum SatLogTransport: String, CaseIterable, Codable, Sendable, Identifiable {
    case udp
    case tcp

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .udp: "UDP"
        case .tcp: "TCP"
        }
    }
}

// MARK: - SatLogListenerEvent

/// Events the socket actor reports back to `SatLogListenerService`.
enum SatLogListenerEvent: Sendable {
    case ready(port: UInt16)
    /// Complete ADIF record strings (each ending in `<eor>`) and who sent them.
    case records([String], sender: String)
    case waiting(String)
    case failed(String)
}

// MARK: - SatLogListenerError

enum SatLogListenerError: LocalizedError {
    case invalidPort(UInt16)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .invalidPort(port):
            "Port \(port) is not usable"
        }
    }
}

// MARK: - SatLogListener

actor SatLogListener {
    // MARK: Lifecycle

    init(
        transport: SatLogTransport,
        port: UInt16,
        onEvent: @escaping @Sendable (SatLogListenerEvent) -> Void
    ) {
        self.transport = transport
        self.port = port
        self.onEvent = onEvent
    }

    // MARK: Internal

    let transport: SatLogTransport
    let port: UInt16

    /// Bind the socket. Idempotent; readiness is reported via `.ready`.
    func start() throws {
        guard listener == nil else {
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port), port > 0 else {
            throw SatLogListenerError.invalidPort(port)
        }
        let parameters: NWParameters = transport == .udp ? .udp : .tcp
        parameters.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: parameters, on: nwPort)
        newListener.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleListenerState(state) }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        listener = newListener
        newListener.start(queue: queue)
    }

    /// Close the socket and every open connection. Trailing partial TCP
    /// records are flushed first.
    func stop() {
        listener?.cancel()
        listener = nil
        for id in Array(connections.keys) {
            finish(id)
        }
    }

    // MARK: Private

    private struct ConnectionState {
        let connection: NWConnection
        let sender: String
        var buffer = SatLogRecordBuffer()
    }

    private let onEvent: @Sendable (SatLogListenerEvent) -> Void
    private let queue = DispatchQueue(label: "com.jsvana.CWSweep.SatLog", qos: .utility)

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ConnectionState] = [:]

    private static func describe(_ endpoint: NWEndpoint) -> String {
        if case let .hostPort(host, port) = endpoint {
            return "\(host):\(port)"
        }
        return "\(endpoint)"
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            let bound = listener?.port?.rawValue ?? port
            let name = transport.rawValue
            logger.info("S.A.T. \(name, privacy: .public) listener ready on port \(bound)")
            onEvent(.ready(port: bound))
        case let .waiting(error):
            logger.warning("S.A.T. listener waiting: \(error.localizedDescription, privacy: .public)")
            onEvent(.waiting(error.localizedDescription))
        case let .failed(error):
            logger.error("S.A.T. listener failed: \(error.localizedDescription, privacy: .public)")
            stop()
            onEvent(.failed(error.localizedDescription))
        case .setup,
             .cancelled:
            break
        @unknown default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = ConnectionState(
            connection: connection,
            sender: Self.describe(connection.endpoint)
        )
        connection.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleConnectionState(state, id: id) }
        }
        connection.start(queue: queue)
        receiveNext(on: connection, id: id)
    }

    private func receiveNext(on connection: NWConnection, id: ObjectIdentifier) {
        switch transport {
        case .udp:
            connection.receiveMessage { [weak self] data, _, _, error in
                Task { await self?.handleDatagram(data, error: error, connection: connection, id: id) }
            }
        case .tcp:
            connection.receive(
                minimumIncompleteLength: 1, maximumLength: 65_536
            ) { [weak self] data, _, isComplete, error in
                Task {
                    await self?.handleStreamChunk(
                        data, isComplete: isComplete, error: error, connection: connection, id: id
                    )
                }
            }
        }
    }

    private func handleDatagram(
        _ data: Data?, error: NWError?, connection: NWConnection, id: ObjectIdentifier
    ) {
        if let error {
            logger.warning("S.A.T. UDP receive error: \(error.localizedDescription, privacy: .public)")
            finish(id)
            return
        }
        if let data, !data.isEmpty {
            emit(SatLogRecordBuffer.records(inDatagram: data), id: id)
        }
        guard connections[id] != nil else {
            return
        }
        receiveNext(on: connection, id: id)
    }

    private func handleStreamChunk(
        _ data: Data?, isComplete: Bool, error: NWError?, connection: NWConnection, id: ObjectIdentifier
    ) {
        if let data, !data.isEmpty, var state = connections[id] {
            let records = state.buffer.append(data)
            connections[id] = state
            emit(records, id: id)
        }
        if let error {
            logger.warning("S.A.T. TCP receive error: \(error.localizedDescription, privacy: .public)")
            finish(id)
            return
        }
        if isComplete {
            finish(id)
            return
        }
        guard connections[id] != nil else {
            return
        }
        receiveNext(on: connection, id: id)
    }

    private func handleConnectionState(_ state: NWConnection.State, id: ObjectIdentifier) {
        switch state {
        case .failed,
             .cancelled:
            finish(id)
        default:
            break
        }
    }

    /// Flush a closing connection's trailing partial record, then drop it.
    private func finish(_ id: ObjectIdentifier) {
        guard var state = connections.removeValue(forKey: id) else {
            return
        }
        emit(state.buffer.flush(), id: id, sender: state.sender)
        state.connection.cancel()
    }

    private func emit(_ records: [String], id: ObjectIdentifier, sender: String? = nil) {
        guard !records.isEmpty else {
            return
        }
        let who = sender ?? connections[id]?.sender ?? "unknown"
        onEvent(.records(records, sender: who))
    }
}
