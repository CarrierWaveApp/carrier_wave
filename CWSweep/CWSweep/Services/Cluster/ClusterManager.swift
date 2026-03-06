import Foundation

// MARK: - ClusterManager

/// Manages DX cluster connection state and feeds spots into SpotAggregator.
@MainActor
@Observable
final class ClusterManager {
    // MARK: Internal

    // MARK: - Published State

    private(set) var connectionState: ClusterConnectionState = .disconnected
    private(set) var scrollback: [ClusterLine] = []
    private(set) var parsedSpots: [DXClusterSpot] = []
    private(set) var selectedNode: ClusterNode?

    /// Aggregator to feed spots into (set by WorkspaceView)
    var spotAggregator: SpotAggregator?

    /// Maximum scrollback lines
    var maxScrollback = 500

    /// Whether currently connected
    var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    // MARK: - Public API

    /// Connect to a cluster node
    func connect(node: ClusterNode, callsign: String) {
        selectedNode = node
        let client = telnetClient

        Task {
            await client.connect(
                node: node,
                callsign: callsign,
                onLine: { [weak self] line in
                    Task { @MainActor in
                        self?.appendLine(line, isSpot: false)
                    }
                },
                onStateChange: { [weak self] state in
                    Task { @MainActor in
                        self?.connectionState = state
                    }
                },
                onSpot: { [weak self] spot in
                    Task { @MainActor in
                        self?.handleSpot(spot)
                    }
                }
            )
        }
    }

    /// Disconnect from the cluster
    func disconnect() {
        Task {
            await telnetClient.disconnect()
        }
        selectedNode = nil
    }

    /// Send a raw command
    func sendCommand(_ command: String) {
        Task {
            await telnetClient.send(command)
        }
        appendLine("> \(command)", isSpot: false)
    }

    /// Clear scrollback
    func clearScrollback() {
        scrollback.removeAll()
    }

    // MARK: Private

    private let telnetClient = TelnetClusterClient()

    private func appendLine(_ text: String, isSpot: Bool) {
        let line = ClusterLine(text: text, isSpot: isSpot, timestamp: Date())
        scrollback.append(line)

        // Trim scrollback
        if scrollback.count > maxScrollback {
            scrollback.removeFirst(scrollback.count - maxScrollback)
        }
    }

    private func handleSpot(_ spot: DXClusterSpot) {
        parsedSpots.append(spot)
        spotAggregator?.addClusterSpots([spot.toUnifiedSpot()])
        appendLine(
            "DX de \(spot.spotter): \(String(format: "%.1f", spot.frequencyKHz)) \(spot.callsign) \(spot.comment)",
            isSpot: true
        )

        // Trim parsed spots
        if parsedSpots.count > 500 {
            parsedSpots.removeFirst(parsedSpots.count - 500)
        }
    }
}

// MARK: - ClusterLine

/// A line in the cluster scrollback
struct ClusterLine: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let isSpot: Bool
    let timestamp: Date
}
