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
    private(set) var solarWeather: [SolarWeatherEntry] = []
    private(set) var solarFetchedAt: Date?
    private(set) var filterConfig: ClusterFilterConfig?

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
                        self?.handleLine(line)
                    }
                },
                onStateChange: { [weak self] state in
                    Task { @MainActor in
                        self?.handleStateChange(state)
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
        pendingResponse = nil
        responseBuffer.removeAll()
        solarWeather.removeAll()
        solarFetchedAt = nil
        filterConfig = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Send a raw command
    func sendCommand(_ command: String) {
        let upper = command.uppercased()

        // Track pending response for parseable commands
        if upper.hasPrefix("SH/WWV") || upper.hasPrefix("SH/WCY") {
            pendingResponse = .wwv
            responseBuffer.removeAll()
        } else if upper.hasPrefix("SH/FILTER") || upper.hasPrefix("SH/FI") {
            pendingResponse = .filter
            responseBuffer.removeAll()
        }

        Task {
            await telnetClient.send(command)
        }
        appendLine("> \(command)", isSpot: false)
    }

    /// Refresh solar weather and filter config
    func refreshStatus() {
        sendCommand("SH/WWV")
        // Delay filter query slightly to avoid interleaving
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard isConnected else {
                return
            }
            sendCommand("SH/FILTER")
        }
    }

    /// Clear scrollback
    func clearScrollback() {
        scrollback.removeAll()
    }

    // MARK: Private

    private enum PendingResponseType {
        case wwv
        case filter
    }

    private let telnetClient = TelnetClusterClient()
    private var pendingResponse: PendingResponseType?
    private var responseBuffer: [String] = []
    private var refreshTask: Task<Void, Never>?

    private func handleStateChange(_ state: ClusterConnectionState) {
        connectionState = state

        if case .connected = state {
            // Auto-send info commands after a brief delay for login to complete
            refreshTask?.cancel()
            refreshTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, isConnected else {
                    return
                }
                refreshStatus()
                // Then refresh every 5 minutes
                while !Task.isCancelled, isConnected {
                    try? await Task.sleep(for: .seconds(300))
                    guard !Task.isCancelled, isConnected else {
                        break
                    }
                    refreshStatus()
                }
            }
        }
    }

    private func handleLine(_ line: String) {
        appendLine(line, isSpot: false)

        // If we're collecting a response, try to buffer it
        if let pending = pendingResponse {
            bufferResponseLine(line, type: pending)
        }
    }

    private func bufferResponseLine(_ line: String, type: PendingResponseType) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Skip empty lines
        guard !trimmed.isEmpty else {
            return
        }

        switch type {
        case .wwv:
            if ClusterResponseParser.isWWVHeader(trimmed) {
                // Header line, skip but keep collecting
                return
            }
            if ClusterResponseParser.isWWVLine(trimmed) {
                responseBuffer.append(line)
            } else if !responseBuffer.isEmpty {
                // Non-WWV line after collecting data — parse and finish
                finishWWVResponse()
            } else if trimmed.hasPrefix("DX de") || trimmed.hasPrefix(">") {
                // Spot or command echo — no WWV data came, abort
                pendingResponse = nil
                responseBuffer.removeAll()
            }

        case .filter:
            if ClusterResponseParser.isFilterLine(trimmed)
                || trimmed.hasPrefix("DX configuration")
            {
                responseBuffer.append(line)
            } else if !responseBuffer.isEmpty {
                finishFilterResponse()
            } else if trimmed.hasPrefix("DX de") || trimmed.hasPrefix(">") {
                pendingResponse = nil
                responseBuffer.removeAll()
            }
        }
    }

    private func finishWWVResponse() {
        let entries = ClusterResponseParser.parseWWV(lines: responseBuffer)
        if !entries.isEmpty {
            solarWeather = entries
            solarFetchedAt = Date()
        }
        pendingResponse = nil
        responseBuffer.removeAll()
    }

    private func finishFilterResponse() {
        if let config = ClusterResponseParser.parseFilter(lines: responseBuffer) {
            filterConfig = config
        }
        pendingResponse = nil
        responseBuffer.removeAll()
    }

    private func appendLine(_ text: String, isSpot: Bool) {
        let line = ClusterLine(text: text, isSpot: isSpot, timestamp: Date())
        scrollback.append(line)

        // Trim scrollback
        if scrollback.count > maxScrollback {
            scrollback.removeFirst(scrollback.count - maxScrollback)
        }
    }

    private func handleSpot(_ spot: DXClusterSpot) {
        parsedSpots.insert(spot, at: 0)
        spotAggregator?.addClusterSpots([spot.toUnifiedSpot()])
        appendLine(
            "DX de \(spot.spotter): \(String(format: "%.1f", spot.frequencyKHz)) \(spot.callsign) \(spot.comment)",
            isSpot: true
        )

        // If we were collecting a response and a spot interrupts, finalize
        if let pending = pendingResponse {
            switch pending {
            case .wwv: finishWWVResponse()
            case .filter: finishFilterResponse()
            }
        }

        // Trim oldest parsed spots
        if parsedSpots.count > 500 {
            parsedSpots.removeLast(parsedSpots.count - 500)
        }
    }
}

// MARK: - ClusterLine

/// A line in the cluster scrollback
struct ClusterLine: Identifiable {
    let id = UUID()
    let text: String
    let isSpot: Bool
    let timestamp: Date
}
