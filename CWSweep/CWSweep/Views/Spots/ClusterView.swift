import SwiftUI

// MARK: - ClusterViewMode

/// View mode for the cluster display
private enum ClusterViewMode: String, CaseIterable, Identifiable {
    case smart
    case allSpots
    case raw

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .smart: "Smart"
        case .allSpots: "All Spots"
        case .raw: "Raw"
        }
    }
}

// MARK: - ClusterView

/// Telnet DX cluster connection and spot display
struct ClusterView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            connectionBar
            Divider()
            viewModeBar
            Divider()

            Group {
                switch viewMode {
                case .smart:
                    smartSpotTableView
                case .allSpots:
                    spotTableView
                case .raw:
                    scrollbackView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(ClusterManager.self) private var clusterManager
    @Environment(RadioManager.self) private var radioManager
    @AppStorage("myCallsign") private var myCallsign = ""
    @AppStorage("autoXITEnabled") private var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") private var autoXITOffsetHz = 0
    @State private var selectedNode: ClusterNode = .presets[0]
    @State private var commandText = ""
    @State private var viewMode: ClusterViewMode = .smart
    @State private var selectedBand = "All"
    @State private var selectedMode: SpotModeFilter = .all
    @State private var filterText = ""

    private let commonBands = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m",
    ]

    // MARK: - Smart Spots

    private var smartSpots: [DXClusterSpot] {
        // Dedup by callsign+band, keeping newest
        var seen: [String: DXClusterSpot] = [:]
        for spot in clusterManager.parsedSpots {
            let key = spot.dedupKey
            if let existing = seen[key] {
                if spot.timestamp > existing.timestamp {
                    seen[key] = spot
                }
            } else {
                seen[key] = spot
            }
        }

        var spots = Array(seen.values)

        // Apply filters
        if selectedBand != "All" {
            spots = spots.filter { $0.band == selectedBand }
        }

        if selectedMode != .all {
            spots = spots.filter { selectedMode.matches(mode: $0.parsedMode) }
        }

        if !filterText.isEmpty {
            let query = filterText.lowercased()
            spots = spots.filter {
                $0.callsign.lowercased().contains(query)
                    || $0.spotter.lowercased().contains(query)
                    || $0.comment.lowercased().contains(query)
            }
        }

        return spots.sorted { $0.timestamp > $1.timestamp }
    }

    private var spotCountForMode: Int {
        switch viewMode {
        case .smart: smartSpots.count
        case .allSpots: clusterManager.parsedSpots.count
        case .raw: clusterManager.scrollback.count
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch clusterManager.connectionState {
        case .connected: .green
        case .connecting: .yellow
        case .disconnected: .red
        case .failed: .red
        }
    }

    private var statusText: String {
        switch clusterManager.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnected: "Disconnected"
        case let .failed(msg): "Failed: \(msg)"
        }
    }

    // MARK: - Connection Bar

    private var connectionBar: some View {
        HStack(spacing: 12) {
            // Node picker
            Picker("Node", selection: $selectedNode) {
                ForEach(ClusterNode.presets) { node in
                    Text(node.name).tag(node)
                }
            }
            .frame(width: 120)

            // Connection status
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cluster status: \(statusText)")

            // Connect/Disconnect button
            if clusterManager.isConnected {
                Button("Disconnect") {
                    clusterManager.disconnect()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Connect") {
                    guard !myCallsign.isEmpty else {
                        return
                    }
                    clusterManager.connect(node: selectedNode, callsign: myCallsign)
                }
                .buttonStyle(.borderedProminent)
                .disabled(myCallsign.isEmpty)
                .help(myCallsign.isEmpty ? "Set your callsign in Settings first" : "Connect to cluster node")
            }

            Spacer()

            // Command input
            if clusterManager.isConnected {
                HStack {
                    TextField("Cluster command", text: $commandText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit {
                            guard !commandText.isEmpty else {
                                return
                            }
                            clusterManager.sendCommand(commandText)
                            commandText = ""
                        }
                }
            }

            // Clear scrollback
            Button {
                clusterManager.clearScrollback()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Clear scrollback")
            .help("Clear scrollback")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - View Mode Bar

    private var viewModeBar: some View {
        HStack(spacing: 8) {
            Picker(selection: $viewMode) {
                ForEach(ClusterViewMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            if viewMode == .smart {
                // Band filter
                Picker("Band", selection: $selectedBand) {
                    Text("All").tag("All")
                    ForEach(commonBands, id: \.self) { band in
                        Text(band).tag(band)
                    }
                }
                .labelsHidden()
                .frame(width: 75)

                // Mode filter
                Picker(selection: $selectedMode) {
                    ForEach(SpotModeFilter.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter...", text: $filterText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 150)
            }

            Spacer()

            // Spot count
            Text("\(spotCountForMode)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var smartSpotTableView: some View {
        Group {
            if smartSpots.isEmpty {
                ContentUnavailableView {
                    Label("No Spots", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    if clusterManager.parsedSpots.isEmpty {
                        Text("Connect to a cluster node to see spots")
                    } else {
                        Text("No spots match the current filters")
                    }
                }
            } else {
                Table(of: DXClusterSpot.self) {
                    TableColumn("Time") { spot in
                        Text(formatTime(spot.timestamp))
                            .font(.caption.monospacedDigit())
                    }
                    .width(min: 35, ideal: 45)

                    TableColumn("Callsign") { spot in
                        Text(spot.callsign)
                            .fontWeight(.medium)
                    }
                    .width(min: 70, ideal: 90)

                    TableColumn("Freq") { spot in
                        Text(String(format: "%.1f", spot.frequencyKHz))
                            .monospacedDigit()
                    }
                    .width(min: 55, ideal: 70)

                    TableColumn("Mode") { spot in
                        Text(spot.parsedMode)
                            .font(.caption)
                    }
                    .width(min: 35, ideal: 50)

                    TableColumn("Speed") { spot in
                        if let wpm = spot.cwSpeed {
                            Text("\(wpm) WPM")
                                .font(.caption.monospacedDigit())
                        } else {
                            Text("\u{2014}")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 50, ideal: 60)

                    TableColumn("Band") { spot in
                        Text(spot.band)
                            .font(.caption)
                    }
                    .width(min: 30, ideal: 40)

                    TableColumn("Spotter") { spot in
                        Text(spot.spotter)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Comment") { spot in
                        Text(spot.comment)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 80, ideal: 120)
                } rows: {
                    ForEach(smartSpots) { spot in
                        TableRow(spot)
                            .contextMenu {
                                tuneAndLogButton(for: spot)
                            }
                    }
                }
                .alternatingRowBackgrounds()
            }
        }
    }

    // MARK: - Scrollback

    private var scrollbackView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(clusterManager.scrollback) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.isSpot ? Color.primary : Color.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .id(line.id)
                        }
                    }
                }
                .onChange(of: clusterManager.scrollback.count) { _, _ in
                    if let last = clusterManager.scrollback.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(.background.secondary)
    }

    // MARK: - Parsed Spots Table (All Spots mode)

    private var spotTableView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(of: DXClusterSpot.self) {
                TableColumn("Time") { spot in
                    Text(formatTime(spot.timestamp))
                        .font(.caption.monospacedDigit())
                }
                .width(min: 35, ideal: 45)

                TableColumn("Callsign") { spot in
                    Text(spot.callsign)
                        .fontWeight(.medium)
                }
                .width(min: 70, ideal: 90)

                TableColumn("Freq") { spot in
                    Text(String(format: "%.1f", spot.frequencyKHz))
                        .monospacedDigit()
                }
                .width(min: 55, ideal: 70)

                TableColumn("Mode") { spot in
                    Text(spot.parsedMode)
                        .font(.caption)
                }
                .width(min: 35, ideal: 50)

                TableColumn("Spotter") { spot in
                    Text(spot.spotter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 80)

                TableColumn("Comment") { spot in
                    Text(spot.comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 120)
            } rows: {
                ForEach(clusterManager.parsedSpots.reversed()) { spot in
                    TableRow(spot)
                        .contextMenu {
                            tuneAndLogButton(for: spot)
                        }
                }
            }
            .alternatingRowBackgrounds()
        }
    }

    // MARK: - Shared Actions

    private func tuneAndLogButton(for spot: DXClusterSpot) -> some View {
        Button("Tune & Log") {
            Task {
                try? await radioManager.tuneToFrequency(spot.frequencyMHz)
                try? await radioManager.setMode(spot.parsedMode)
                if autoXITEnabled, autoXITOffsetHz != 0 {
                    try? await radioManager.setXITOffset(autoXITOffsetHz)
                    try? await radioManager.setXIT(true)
                } else if autoXITEnabled {
                    try? await radioManager.setXIT(false)
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}

// MARK: - ClusterPanel

/// Standalone cluster window
struct ClusterPanel: View {
    var body: some View {
        ClusterView()
            .frame(minWidth: 600, minHeight: 400)
    }
}
