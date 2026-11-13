import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CarrierWaveData", category: "Rotator")

// MARK: - RotatorTransportError

public enum RotatorTransportError: LocalizedError, Sendable {
    case invalidEndpoint(String)
    case notConnected
    case timeout
    case connectionFailed(String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(detail): "Bad rotator address: \(detail)"
        case .notConnected: "Rotator not connected"
        case .timeout: "Rotator did not answer"
        case let .connectionFailed(detail): "Rotator connection failed: \(detail)"
        }
    }
}

// MARK: - RotatorTransport

/// Request/response link to one rotator. Both the TCP (Hamlib) and UDP
/// (PSR-100) implementations serialize commands so a position poll never
/// interleaves with a move.
public protocol RotatorTransport: Actor {
    func connect() async throws
    func disconnect() async
    /// Send a command and wait up to `timeout` for one reply datagram/line
    /// group. Fire-and-forget callers pass `expectReply: false`.
    func send(_ data: Data, expectReply: Bool, timeout: Duration) async throws -> String?
}

// MARK: - RotctlTCPTransport

/// Hamlib `rotctld` over TCP. The S.A.T. (port 4533) and any PC running
/// `rotctld` speak this. Replies are newline terminated; `p` answers with two
/// lines, so the reader collects until the expected line count or a quiet
/// gap.
public actor RotctlTCPTransport: RotatorTransport {
    // MARK: Lifecycle

    public init(host: String, port: UInt16 = 4_533) {
        self.host = host
        self.port = port
    }

    // MARK: Public

    public func connect() async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw RotatorTransportError.invalidEndpoint("\(host):\(port)")
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.connectionTimeout = 5
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        connection = conn
        try await Self.awaitReady(conn, timeout: .seconds(5))
        startReceiving(on: conn)
    }

    public func disconnect() async {
        connection?.cancel()
        connection = nil
        pending.removeAll()
    }

    public func send(_ data: Data, expectReply: Bool, timeout: Duration) async throws -> String? {
        guard let connection else {
            throw RotatorTransportError.notConnected
        }
        pending.removeAll()
        try await Self.write(data, to: connection)
        guard expectReply else {
            return nil
        }
        // Hamlib replies arrive as one or two lines; wait for the first then
        // allow a short settle for the second (the `p` elevation line).
        let deadline = ContinuousClock.now + timeout
        while pending.isEmpty {
            guard ContinuousClock.now < deadline else {
                throw RotatorTransportError.timeout
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let settle = ContinuousClock.now + .milliseconds(60)
        while ContinuousClock.now < settle {
            try await Task.sleep(for: .milliseconds(10))
        }
        let reply = pending.joined()
        pending.removeAll()
        return reply
    }

    // MARK: Private

    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private var pending: [String] = []

    private static func awaitReady(_ connection: NWConnection, timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    let box = ContinuationBox(cont)
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            box.resume()
                        case let .failed(error):
                            box.resume(throwing: RotatorTransportError.connectionFailed(error.localizedDescription))
                        case let .waiting(error):
                            box.resume(throwing: RotatorTransportError.connectionFailed(error.localizedDescription))
                        case .cancelled:
                            box.resume(throwing: RotatorTransportError.connectionFailed("cancelled"))
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                connection.cancel()
                throw RotatorTransportError.timeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private static func write(_ data: Data, to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: RotatorTransportError.connectionFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }
            if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                Task { await self.append(text) }
            }
            if error != nil || isComplete {
                logger.info("rotctld link closed: \(String(describing: error))")
                return
            }
            Task { await self.startReceiving(on: connection) }
        }
    }

    private func append(_ text: String) {
        pending.append(text)
    }
}

// MARK: - UDPRotatorTransport

/// UDP link for the PSR-100 Mk2 (and anything speaking EasyComm / GS-232 /
/// S.A.T. XML over UDP). Binds the local port to the rotor's "TX port" so a
/// reply addressed to that fixed port and a reply to our source port both
/// land on this socket.
public actor UDPRotatorTransport: RotatorTransport {
    // MARK: Lifecycle

    public init(host: String, port: UInt16, replyPort: UInt16?) {
        self.host = host
        self.port = port
        self.replyPort = replyPort
    }

    // MARK: Public

    public func connect() async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw RotatorTransportError.invalidEndpoint("\(host):\(port)")
        }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        if let replyPort, let local = NWEndpoint.Port(rawValue: replyPort) {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.any), port: local)
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        connection = conn
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    let box = ContinuationBox(cont)
                    conn.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            box.resume()
                        case let .failed(error):
                            box.resume(throwing: RotatorTransportError.connectionFailed(error.localizedDescription))
                        case let .waiting(error):
                            // UDP "waiting" usually means the local port is
                            // busy (another client bound 2391); surface it.
                            box.resume(throwing: RotatorTransportError.connectionFailed(error.localizedDescription))
                        case .cancelled:
                            box.resume(throwing: RotatorTransportError.connectionFailed("cancelled"))
                        default:
                            break
                        }
                    }
                    conn.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                conn.cancel()
                throw RotatorTransportError.timeout
            }
            try await group.next()
            group.cancelAll()
        }
        receiveLoop(on: conn)
    }

    public func disconnect() async {
        connection?.cancel()
        connection = nil
        pending.removeAll()
    }

    public func send(_ data: Data, expectReply: Bool, timeout: Duration) async throws -> String? {
        guard let connection else {
            throw RotatorTransportError.notConnected
        }
        pending.removeAll()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: RotatorTransportError.connectionFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
        guard expectReply else {
            return nil
        }
        let deadline = ContinuousClock.now + timeout
        while pending.isEmpty {
            guard ContinuousClock.now < deadline else {
                throw RotatorTransportError.timeout
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let reply = pending.joined(separator: "\n")
        pending.removeAll()
        return reply
    }

    // MARK: Private

    private let host: String
    private let port: UInt16
    private let replyPort: UInt16?
    private var connection: NWConnection?
    private var pending: [String] = []

    private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else {
                return
            }
            if let data, let text = String(data: data, encoding: .utf8) {
                Task { await self.append(text) }
            }
            if error != nil {
                return
            }
            Task { await self.receiveLoop(on: connection) }
        }
    }

    private func append(_ text: String) {
        pending.append(text)
    }
}

// MARK: - PSR100HTTPTransport

/// WA4MCM PSR-100 Mk2 over its built-in web server (port 8080). The rotor's
/// own page drives it with `GET /command?cmd=…` and reads `GET /data`; so do
/// we. HTTP is connection-oriented, so unlike the rotor's UDP replies it
/// crosses VLAN boundaries and needs no reply-port configuration.
public actor PSR100HTTPTransport: RotatorTransport {
    // MARK: Lifecycle

    public init(host: String, port: UInt16 = 8_080) {
        self.host = host
        self.port = port
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // MARK: Public

    public func connect() async throws {
        guard let url = URL(string: "http://\(host):\(port)/data") else {
            throw RotatorTransportError.invalidEndpoint("\(host):\(port)")
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  String(bytes: data, encoding: .utf8)?.contains("azimuth") == true
            else {
                throw RotatorTransportError.connectionFailed("unexpected reply from \(host):\(port)/data")
            }
        } catch let error as RotatorTransportError {
            throw error
        } catch {
            throw RotatorTransportError.connectionFailed(error.localizedDescription)
        }
        connected = true
    }

    public func disconnect() async {
        connected = false
    }

    public func send(_ data: Data, expectReply _: Bool, timeout: Duration) async throws -> String? {
        guard connected else {
            throw RotatorTransportError.notConnected
        }
        let command = String(bytes: data, encoding: .utf8) ?? ""
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        if command == RotatorProtocolCodec.statusQueryToken {
            components.path = "/data"
        } else {
            components.path = "/command"
            components.queryItems = [URLQueryItem(name: "cmd", value: command)]
        }
        guard let url = components.url else {
            throw RotatorTransportError.invalidEndpoint(command)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1e18
        do {
            let (body, response) = try await session.data(for: request)
            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                throw RotatorTransportError.connectionFailed("HTTP \(status) from \(host):\(port)")
            }
            return String(bytes: body, encoding: .utf8) ?? ""
        } catch let error as RotatorTransportError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw RotatorTransportError.timeout
        } catch {
            throw RotatorTransportError.connectionFailed(error.localizedDescription)
        }
    }

    // MARK: Private

    private let host: String
    private let port: UInt16
    private let session: URLSession
    private var connected = false
}

// MARK: - ContinuationBox

/// Resume-once guard: Network framework can report `.waiting` and later
/// `.ready` (or `.failed` twice) for one connection attempt.
final class ContinuationBox: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    // MARK: Internal

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume()
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    // MARK: Private

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
}

// MARK: - Factory

public extension TrackerEndpoint {
    /// Build the transport matching this endpoint's protocol.
    func makeTransport() -> any RotatorTransport {
        switch protocolKind {
        case .hamlibRotctl:
            RotctlTCPTransport(host: host, port: port)
        case .psr100HTTP:
            PSR100HTTPTransport(host: host, port: port)
        case .easycommII,
             .gs232B,
             .csnSATxml:
            UDPRotatorTransport(host: host, port: port, replyPort: replyPort)
        }
    }
}
