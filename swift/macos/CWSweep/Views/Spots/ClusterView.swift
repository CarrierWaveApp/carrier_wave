import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ClusterViewMode

/// View mode for the cluster display (kept for backward compat)
enum ClusterViewMode: String, CaseIterable, Identifiable {
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

// MARK: - ClusterDisplayMode

/// Combined display mode merging view mode + smart sub-mode into one picker.
enum ClusterDisplayMode: String, CaseIterable, Identifiable {
    case smartAggregated
    case smartLive
    case allSpots
    case raw

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .smartAggregated: "Smart"
        case .smartLive: "Live"
        case .allSpots: "All"
        case .raw: "Raw"
        }
    }

    var isSmart: Bool {
        self == .smartAggregated || self == .smartLive
    }
}

// MARK: - ClusterCommand

/// Quick commands available when connected to a cluster node
private enum ClusterCommand: String, CaseIterable, Identifiable {
    case showDX = "SH/DX"
    case showWWV = "SH/WWV"
    case setSkimmer = "SET/SKIMMER"
    case showFilter = "SH/FILTER"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .showDX: "Recent DX"
        case .showWWV: "Solar (WWV)"
        case .setSkimmer: "Skimmer Mode"
        case .showFilter: "Show Filters"
        }
    }

    var icon: String {
        switch self {
        case .showDX: "antenna.radiowaves.left.and.right"
        case .showWWV: "sun.max"
        case .setSkimmer: "waveform"
        case .showFilter: "line.3.horizontal.decrease"
        }
    }
}

// MARK: - ClusterView

/// Telnet DX cluster connection and spot display with RBN enrichment
struct ClusterView: View {
    // MARK: Internal

    @Environment(ClusterManager.self) var clusterManager
    @Environment(SpotAggregator.self) var spotAggregator
    @Environment(RadioManager.self) var radioManager
    @Environment(SelectionState.self) var selectionState
    @Environment(\.modelContext) var modelContext
    @AppStorage("myCallsign") var myCallsign = ""
    @AppStorage("autoXITEnabled") var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") var autoXITOffsetHz = 0
    @State var selectedNode: ClusterNode = .presets[0]
    @State var commandText = ""
    @State var displayMode: ClusterDisplayMode = .smartAggregated
    @State var viewMode: ClusterViewMode = .smart
    @State var selectedBand = "All"
    @State var selectedMode: SpotModeFilter = .all
    @State var selectedContinents: Set<SpotContinent> = []
    @State var selectedRegions: Set<SpotRegionGroup> = []
    @State var filterText = ""
    @State var selectedSpotID: String?
    @State var workedChecker = ClusterWorkedBeforeChecker()
    @State var refreshTrigger = false
    @State var smartAggregated = true
    @State var scrollbackPaused = false
    @State var pausedAtCount = 0
    @State var pausedAtTime: Date?
    @State var isScrolledToBottom = true

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await loadWorkedBefore() }
            .task(id: refreshTrigger) { await periodicRefresh() }
            .onChange(of: selectedSpotID) { _, newId in
                selectionState.selectedSpot = enrichedSmartSpots.first { $0.id == newId }
            }
    }

    // MARK: Private

    private var mainContent: some View {
        VStack(spacing: 0) {
            connectionBar
            Divider()
            if clusterManager.isConnected {
                commandBar
                Divider()
                if hasStatusData {
                    ClusterStatusBar(
                        solarWeather: clusterManager.solarWeather,
                        solarFetchedAt: clusterManager.solarFetchedAt,
                        filterConfig: clusterManager.filterConfig,
                        onRefresh: { clusterManager.refreshStatus() }
                    )
                    Divider()
                }
            }
            viewModeBar
            Divider()

            Group {
                switch viewMode {
                case .smart:
                    if smartAggregated {
                        smartSpotTableView
                    } else {
                        liveFeedTableView
                    }
                case .allSpots:
                    spotTableView
                case .raw:
                    scrollbackView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Connection Bar

    private var connectionBar: some View {
        HStack(spacing: 12) {
            if clusterManager.isConnected, let node = clusterManager.selectedNode {
                // Connected state: show prominent node name
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Connected to \(node.name)")
                        .font(.headline)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Connected to \(node.name)")

                Text(node.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Disconnect") {
                    clusterManager.disconnect()
                }
                .buttonStyle(.bordered)
            } else {
                // Disconnected state: show picker
                Picker("Node", selection: $selectedNode) {
                    ForEach(ClusterNode.presets) { node in
                        Text("\(node.name) — \(node.description)").tag(node)
                    }
                }
                .frame(width: 360)

                connectionStatusView

                Button("Connect") {
                    guard !myCallsign.isEmpty else {
                        return
                    }
                    clusterManager.connect(node: selectedNode, callsign: myCallsign)
                }
                .buttonStyle(.borderedProminent)
                .disabled(myCallsign.isEmpty)
                .help(
                    myCallsign.isEmpty
                        ? "Set your callsign in Settings first"
                        : "Connect to cluster node"
                )

                Spacer()
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

    @ViewBuilder
    private var connectionStatusView: some View {
        if case .connecting = clusterManager.connectionState {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if case let .failed(msg) = clusterManager.connectionState {
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Failed: \(msg)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Command Bar

    private var commandBar: some View {
        HStack(spacing: 8) {
            ForEach(ClusterCommand.allCases) { cmd in
                Button {
                    clusterManager.sendCommand(cmd.rawValue)
                } label: {
                    Label(cmd.label, systemImage: cmd.icon)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(cmd.rawValue)
            }

            Divider()
                .frame(height: 20)

            TextField("Command...", text: $commandText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit {
                    guard !commandText.isEmpty else {
                        return
                    }
                    clusterManager.sendCommand(commandText)
                    commandText = ""
                }
                .help("Send a raw cluster command")

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - View Mode Bar

    private var viewModeBar: some View {
        HStack(spacing: 6) {
            Picker(selection: $displayMode) {
                ForEach(ClusterDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .onChange(of: displayMode) { _, newMode in
                syncDisplayMode(newMode)
            }

            if displayMode.isSmart {
                BandFilterPicker(selectedBand: $selectedBand)

                Picker("Mode", selection: $selectedMode) {
                    ForEach(SpotModeFilter.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 80)

                GeographicFilterDropdowns(
                    selectedContinents: $selectedContinents,
                    selectedRegions: $selectedRegions
                )

                SpotSearchField(text: $filterText, width: 120)
            }

            Spacer()

            spotCountLabel
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var spotCountLabel: some View {
        HStack(spacing: 4) {
            Text("\(spotCountForMode)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            if viewMode == .smart, let age = newestSpotAge {
                Text("· newest \(age) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize()
    }

    private func syncDisplayMode(_ mode: ClusterDisplayMode) {
        switch mode {
        case .smartAggregated:
            viewMode = .smart
            smartAggregated = true
        case .smartLive:
            viewMode = .smart
            smartAggregated = false
        case .allSpots:
            viewMode = .allSpots
        case .raw:
            viewMode = .raw
        }
    }

    // MARK: - Data Loading

    private func loadWorkedBefore() async {
        let container = modelContext.container
        await workedChecker.loadToday(container: container)
    }

    private func periodicRefresh() async {
        // Refresh worked-before cache every 60 seconds
        try? await Task.sleep(for: .seconds(60))
        guard !Task.isCancelled else {
            return
        }
        await loadWorkedBefore()
        refreshTrigger.toggle()
    }
}

// MARK: - ClusterPanel

/// Standalone cluster window
struct ClusterPanel: View {
    var body: some View {
        ClusterView()
            .frame(minWidth: 700, minHeight: 400)
    }
}
