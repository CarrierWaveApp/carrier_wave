import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CarrierWaveData", category: "FlexTransport")

// MARK: - FlexRadioTransport

/// TCP transport for FlexRadio SmartSDR API (port 4992).
/// Implements RadioTransport so RadioSession can drive it identically to serial.
public actor FlexRadioTransport: RadioTransport {
    // MARK: Lifecycle

    public init(
        host: String,
        port: UInt16 = 4_992,
        useTLS: Bool = false,
        logCallback: (@Sendable (String, String) -> Void)? = nil
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.logCallback = logCallback

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        receivedData = stream
        self.continuation = continuation
    }

    // MARK: Public

    nonisolated public let receivedData: AsyncStream<Data>

    public var isConnected: Bool {
        connected
    }

    public func connect() async throws {
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: makeConnectionParams()
        )
        connection = conn

        // GCD timeout — cancels the connection if it doesn't complete in 10s
        let timeoutItem = DispatchWorkItem { [weak conn] in
            logger.error("Connection timed out to \(self.host):\(self.port)")
            conn?.cancel()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeoutItem)

        do {
            try await awaitReady(conn)
            timeoutItem.cancel()
        } catch {
            timeoutItem.cancel()
            throw FlexTransportError.connectionTimeout
        }

        connected = true
        startReceiving()
    }

    public func disconnect() async {
        connection?.cancel()
        connection = nil
        connected = false
        continuation.finish()
    }

    public func send(_ data: Data) async throws {
        guard let connection else {
            throw FlexTransportError.notConnected
        }
        let text = String(data: data, encoding: .utf8) ?? "<binary>"
        let trimmed = text.trimmingCharacters(in: .newlines)
        logger.debug("SEND: \(trimmed)")
        logCallback?("TX", trimmed)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    // MARK: Private

    private let host: String
    private let port: UInt16
    private let useTLS: Bool
    private let logCallback: (@Sendable (String, String) -> Void)?
    private let continuation: AsyncStream<Data>.Continuation
    private var connection: NWConnection?
    private var connected = false

    private func makeConnectionParams() -> NWParameters {
        let params: NWParameters
        if useTLS {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_peer_authentication_required(
                tlsOptions.securityProtocolOptions, false
            )
            params = NWParameters(tls: tlsOptions)
        } else {
            params = NWParameters.tcp
        }
        // Force IPv4 — Flex radios don't support IPv6
        if let ipOpts = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOpts.version = .v4
        }
        return params
    }

    private func awaitReady(_ conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if !resumed {
                        resumed = true
                        cont.resume()
                    }
                    logger.info("Connected to Flex at \(self?.host ?? "?"):\(self?.port ?? 0)")

                case let .waiting(error):
                    logger.warning("Connection waiting: \(error.localizedDescription)")

                case let .failed(error):
                    if !resumed {
                        resumed = true
                        cont.resume(throwing: error)
                    } else {
                        Task { await self?.handleDisconnect() }
                    }

                case .cancelled:
                    if !resumed {
                        resumed = true
                        cont.resume(throwing: FlexTransportError.notConnected)
                    }

                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    private func handleDisconnect() {
        connected = false
        continuation.finish()
        logger.info("Flex radio disconnected")
    }

    private func startReceiving() {
        guard let connection else {
            return
        }

        connection
            .receive(
                minimumIncompleteLength: 1,
                maximumLength: 8_192
            ) { [weak self] content, _, isComplete, error in
                Task {
                    if let data = content, !data.isEmpty {
                        await self?.handleReceived(data)
                    }
                    if isComplete || error != nil {
                        await self?.handleDisconnect()
                    } else {
                        await self?.startReceiving()
                    }
                }
            }
    }

    private func handleReceived(_ data: Data) {
        let text = String(data: data, encoding: .utf8) ?? "<binary \(data.count)b>"
        let trimmed = text.trimmingCharacters(in: .newlines)
        logger.debug("RECV: \(trimmed)")
        logCallback?("RX", trimmed)
        continuation.yield(data)
    }
}

// MARK: - FlexTransportError

public enum FlexTransportError: LocalizedError {
    case notConnected
    case connectionTimeout

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to Flex radio"
        case .connectionTimeout:
            "Connection to Flex radio timed out"
        }
    }
}
