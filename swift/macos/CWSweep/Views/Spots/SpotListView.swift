import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SpotListView

/// Spot list showing live POTA/RBN/SOTA/WWFF/Cluster spots from SpotAggregator
struct SpotListView: View {
    // MARK: Internal

    var initialSourceFilter: SpotSourceFilter = .all
    var initialBand: String?
    var initialMode: SpotModeFilter?
    var compact = false

    @Environment(SpotAggregator.self) var spotAggregator
    @Environment(RadioManager.self) var radioManager
    @Environment(SelectionState.self) var selectionState
    @Environment(BandScopeQueryRunner.self) var queryRunner
    @Environment(\.savedQueryStore) var savedQueryStore
    @Environment(\.openWindow) var openWindow
    @Environment(\.modelContext) var modelContext
    @AppStorage("bandScopeFilterMode") var filterMode: BandScopeFilterMode = .widgets
    @State var savedQueries: [SavedQuery] = []
    @State var filterText = ""
    @State var selectedSource: SpotSourceFilter = .all
    @State var selectedBand: String = "All"
    @State var selectedMode: SpotModeFilter = .all
    @State var selectedContinents: Set<SpotContinent> = []
    @State var selectedRegions: Set<SpotRegionGroup> = []
    // Multi-select state for compact mode
    @State var selectedSources: Set<SpotSourceFilter> = []
    @State var selectedBands: Set<String> = []
    @State var selectedModes: Set<SpotModeFilter> = []
    @AppStorage("autoXITEnabled") var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") var autoXITOffsetHz = 0
    @State var selection: Set<EnrichedSpot.ID> = []
    @State var cachedFilteredSpots: [EnrichedSpot] = []
    @State var sortOrder = SpotListOrdering.defaultSortOrder
    /// Operator callsign (Settings → General). Drives self-spot highlighting
    /// and pinning; empty means "no self-spot styling".
    @AppStorage("myCallsign") var myCallsign = ""
    @State var activeParkReference: String?
    /// Tracked width for progressive column hiding
    @State var tableWidth: CGFloat = 900

    // MARK: - Column Visibility

    var showDXCC: Bool {
        tableWidth >= 700
    }

    var showDistBrg: Bool {
        tableWidth >= 700
    }

    var showSpotName: Bool {
        tableWidth >= 550
    }

    var showReference: Bool {
        tableWidth >= 550
    }

    var showStatus: Bool {
        tableWidth >= 550
    }

    var showAge: Bool {
        tableWidth >= 400
    }

    var showSpotMode: Bool {
        tableWidth >= 400
    }

    var body: some View {
        // Split into `content` + `refilterTriggers` so the type checker
        // doesn't time out on one 20-plus-modifier chain (Xcode 26.3).
        refilterTriggers(content)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                tableWidth = newWidth
            }
            .task(id: initialSourceFilter) {
                selectedSource = initialSourceFilter
            }
            .task(id: initialBand) {
                if let initialBand {
                    selectedBand = initialBand
                    selectedBands = [initialBand]
                }
            }
            .task(id: initialMode) {
                if let initialMode {
                    selectedMode = initialMode
                    selectedModes = [initialMode]
                }
            }
            .task { await loadActiveParkReference() }
            .task { await refreshSavedQueries() }
            .onReceive(NotificationCenter.default.publisher(for: .savedQueriesChanged)) { _ in
                Task { await refreshSavedQueries() }
            }
            .onAppear { refilter() }
    }

    // MARK: Private

    private var activeQueryName: String {
        switch filterMode {
        case .widgets:
            "Widgets"
        case let .savedQuery(uuid):
            savedQueries.first(where: { $0.id == uuid })?.name ?? "Unknown query"
        }
    }

    // MARK: - Filter Bar

    /// Wide enough to show all 9 source segments without truncation
    private var useSegmentedSource: Bool {
        tableWidth >= 750
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            // SQL mode: hide every widget filter — the saved query is
            // the source of truth. Widget mode: keep the existing
            // source/band/mode/region pickers.
            if filterMode == .widgets {
                if compact {
                    compactFilterBar
                } else {
                    filterBar
                }
            } else {
                sqlSourceBanner
            }
            Divider()

            if cachedFilteredSpots.isEmpty {
                emptyState
            } else {
                spotTable
            }
        }
    }

    /// Banner shown in place of the widget filter bar while SQL mode
    /// is active. Surfaces which query is driving the list and lets
    /// the user swap back to widgets without hunting for the band
    /// scope's filter pill.
    private var sqlSourceBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Filtered by:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(activeQueryName)
                .font(.caption.bold())
            Spacer()
            if let queryError = queryRunner.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(queryError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Button("Switch to Widgets") {
                filterMode = .widgets
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button {
                openWindow(id: "query-workbench")
            } label: {
                Label("Edit", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Open the query in the Query Workbench")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Spots")
                .font(.headline)

            if let lastRefresh = spotAggregator.lastRefresh {
                Text(lastRefresh, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("\(cachedFilteredSpots.count) / \(spotAggregator.spots.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                Task { await spotAggregator.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Refresh spots")
            .help("Refresh spots")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            // Source filter — segmented when wide, menu when narrow
            if useSegmentedSource {
                Picker(selection: $selectedSource) {
                    ForEach(SpotSourceFilter.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)
                .layoutPriority(-1)
            } else {
                Picker(selection: $selectedSource) {
                    ForEach(SpotSourceFilter.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                } label: {
                    Label("Source", systemImage: "antenna.radiowaves.left.and.right")
                }
                .frame(width: 110)
            }

            BandFilterPicker(selectedBand: $selectedBand)
            ModeFilterPicker(selectedMode: $selectedMode)

            GeographicFilterDropdowns(
                selectedContinents: $selectedContinents,
                selectedRegions: $selectedRegions
            )

            SpotSearchField(text: $filterText, showClearButton: true)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - Compact Filter Bar

    private var compactFilterBar: some View {
        CompactSpotFilterBar(
            selectedSources: $selectedSources,
            selectedBands: $selectedBands,
            selectedModes: $selectedModes,
            filterText: $filterText,
            selectedContinents: $selectedContinents,
            selectedRegions: $selectedRegions
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            if spotAggregator.isPolling, spotAggregator.spots.isEmpty {
                Text("Loading spots...").foregroundStyle(.secondary)
                ProgressView()
            } else if filterText.isEmpty, selectedSource == .all, selectedSources.isEmpty {
                Text("No spots loaded").foregroundStyle(.secondary)
                Text("Spots will appear when polling starts")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                Text("No spots matching filters").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Re-runs the filter whenever any filter input changes. Split in two
    /// (and using the explicit two-argument `onChange` closure) so the type
    /// checker doesn't time out on one long modifier chain.
    private func refilterTriggers(_ view: some View) -> some View {
        refilterOnStateChange(refilterOnSelectionChange(view))
    }

    private func refilterOnSelectionChange(_ view: some View) -> some View {
        view
            .onChange(of: selectedSource) { _, _ in refilter() }
            .onChange(of: selectedBand) { _, _ in refilter() }
            .onChange(of: selectedMode) { _, _ in refilter() }
            .onChange(of: selectedContinents) { _, _ in refilter() }
            .onChange(of: selectedRegions) { _, _ in refilter() }
            .onChange(of: selectedSources) { _, _ in refilter() }
            .onChange(of: selectedBands) { _, _ in refilter() }
            .onChange(of: selectedModes) { _, _ in refilter() }
    }

    private func refilterOnStateChange(_ view: some View) -> some View {
        view
            .onChange(of: filterText) { _, _ in refilter() }
            .onChange(of: sortOrder) { _, _ in refilter() }
            .onChange(of: myCallsign) { _, _ in refilter() }
            .onChange(of: spotAggregator.spots.count) { _, _ in refilter() }
            .onChange(of: spotAggregator.spotsVersion) { _, _ in refilter() }
            .onChange(of: selectionState.vimFilterResult) { _, _ in refilter() }
            .onChange(of: filterMode) { _, _ in refilter() }
            .onChange(of: queryRunner.allowedSpotIDs) { _, _ in refilter() }
    }

    private func refreshSavedQueries() async {
        guard let store = savedQueryStore else {
            return
        }
        savedQueries = await (try? store.list()) ?? []
    }
}
