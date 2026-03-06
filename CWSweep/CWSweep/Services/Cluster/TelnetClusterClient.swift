import Foundation
import Network

// MARK: - ClusterConnectionState

enum ClusterConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

// MARK: - TelnetClusterClient

/// TCP telnet client for DX cluster connections using NWConnection.
actor TelnetClusterClient {
    // MARK: Internal

    // MARK: - Callback types

    typealias LineHandler = @Sendable (String) -> Void
    typealias StateHandler = @Sendable (ClusterConnectionState) -> Void
    typealias SpotHandler = @Sendable (DXClusterSpot) -> Void

    // MARK: - Public API

    /// Connect to a cluster node
    func connect(
        node: ClusterNode,
        callsign: String,
        onLine: @escaping LineHandler,
        onStateChange: @escaping StateHandler,
        onSpot: @escaping SpotHandler
    ) {
        disconnect()

        self.onLine = onLine
        self.onStateChange = onStateChange
        self.onSpot = onSpot
        loginCallsign = callsign

        let params = NWParameters.tcp
        let conn = NWConnection(
            host: NWEndpoint.Host(node.host),
            port: NWEndpoint.Port(rawValue: node.port)!,
            using: params
        )

        conn.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleStateUpdate(state) }
        }

        connection = conn
        onStateChange(.connecting)
        conn.start(queue: .global(qos: .userInitiated))
    }

    /// Disconnect from the cluster
    func disconnect() {
        connection?.cancel()
        connection = nil
        lineBuffer = ""
        onStateChange?(.disconnected)
    }

    /// Send a raw command to the cluster
    func send(_ command: String) {
        guard let connection else {
            return
        }
        let data = Data((command + "\r\n").utf8)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: Private

    // MARK: - Configuration

    private var connection: NWConnection?
    private var lineBuffer = ""
    private var onLine: LineHandler?
    private var onStateChange: StateHandler?
    private var onSpot: SpotHandler?
    private var loginCallsign: String = ""

    private func handleStateUpdate(_ state: NWConnection.State) {
        switch state {
        case .ready:
            onStateChange?(.connected)
            // Auto-login with callsign
            send(loginCallsign)
            startReceiving()

        case let .failed(error):
            onStateChange?(.failed(error.localizedDescription))

        case .cancelled:
            onStateChange?(.disconnected)

        case .waiting:
            onStateChange?(.connecting)

        default:
            break
        }
    }

    private func startReceiving() {
        guard let connection else {
            return
        }

        connection
            .receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] content, _, isComplete, error in
                Task {
                    if let data = content, let text = String(data: data, encoding: .utf8) {
                        await self?.processReceivedText(text)
                    }

                    if isComplete || error != nil {
                        await self?.disconnect()
                    } else {
                        await self?.startReceiving()
                    }
                }
            }
    }

    private func processReceivedText(_ text: String) {
        lineBuffer += text

        // Split on \r\n, \r, or \n using unicodeScalars to avoid Swift's
        // grapheme clustering which treats \r\n as a single Character.
        while let range = lineBuffer.range(of: "\r\n") ??
            lineBuffer.range(of: "\r") ??
            lineBuffer.range(of: "\n")
        {
            let line = String(lineBuffer[lineBuffer.startIndex ..< range.lowerBound])
            lineBuffer = String(lineBuffer[range.upperBound...])

            // Skip empty lines from \r\n
            if line.isEmpty {
                continue
            }

            onLine?(line)

            // Try to parse as a DX spot
            if let spot = DXSpotParser.parse(line: line) {
                onSpot?(spot)
            }
        }
    }
}
