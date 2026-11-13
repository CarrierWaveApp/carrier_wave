import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ContestBandScopeView

/// Vertical-axis band scope optimized for contest S&P workflow.
/// Frequency on y-axis, callsign labels at their frequency position.
/// Keyboard navigation: arrow keys for spots, option+arrows for mults only.
/// Click-to-tune via RadioManager. Supports dual VFO (V5), mini-map rail,
/// cursor crosshair, watch markers, and per-band zoom state preservation.
struct ContestBandScopeView: View {
    // MARK: Internal

    static let axisWidth: CGFloat = 50
    static let miniMapWidth: CGFloat = 38

    @Environment(SpotAggregator.self) var spotAggregator
    @Environment(RadioManager.self) var radioManager
    @Environment(SelectionState.self) var selectionState

    @AppStorage("bandScopeColorMode") var colorMode: BandScopeColorMode = .source
    @AppStorage("bandScopeMaxAgeMinutes") var maxAgeMinutes: Int = 30
    @AppStorage("bandScopeStatusFilter") var statusFilter: SpotStatusFilter = .all
    @AppStorage("bandScopeFilterMode") var filterMode: BandScopeFilterMode = .widgets
    @AppStorage("autoXITEnabled") var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") var autoXITOffsetHz = 0
    @Environment(BandScopeQueryRunner.self) var queryRunner
    @Environment(\.savedQueryStore) var savedQueryStore
    @Environment(\.openWindow) var openWindow
    @State var savedQueries: [SavedQuery] = []
    /// Set of saved-query IDs whose statement returns a `spot_id`
    /// column. Computed lazily after `refreshSavedQueries` and used
    /// to disable picker rows for queries that can't drive the scope.
    @State var validQueryIDs: Set<UUID> = []

    /// Whether to show the summary bar (hidden when band rail is visible in hybrid mode)
    var showSummaryBar: Bool = true

    /// Zoom level (1.0 = full band, higher = zoomed in)
    @State var zoomScale: CGFloat = 1.0

    @State var selectedBandId: String = "20m"
    /// Written by the Canvas on each draw; see `SpotHitRects` for why it isn't `@State` data.
    @State var hitRects = SpotHitRects()
    /// Pan center as fraction of band height (0.5 = centered)
    @State var panOffset: CGFloat = 0.5
    @State var panBaseOffset: CGFloat = 0.5
    @State var cursorFreqKHz: Double?
    /// Watch markers
    @State var bookmarks: [FrequencyBookmark] = []

    @State var zoomBaseScale: CGFloat = 1.0

    /// Per-band zoom/pan state preservation
    @State var bandZoomStates: [String: PerBandZoomState] = [:]

    @State var showHelp = false
    @State var contextMenuSpot: EnrichedSpot?

    var selectedBand: BandEdge? {
        BandEdges.hfBands.first { $0.id == selectedBandId }
    }

    /// Spots sorted by frequency (low at top)
    var sortedSpots: [EnrichedSpot] {
        spotsOnBand.sorted { $0.spot.frequencyKHz < $1.spot.frequencyKHz }
    }

    var spotsOnBand: [EnrichedSpot] {
        guard let band = selectedBand else {
            return []
        }
        // SQL filter mode: trust the query's allow-list, just clip to
        // the visible band. Falls back to widget filters if the runner
        // hasn't produced an allow-list yet (loading or query failed).
        if filterMode != .widgets, let allowed = queryRunner.allowedSpotIDs {
            return spotAggregator.spots.filter { spot in
                spot.spot.frequencyKHz >= band.lowerKHz
                    && spot.spot.frequencyKHz <= band.upperKHz
                    && allowed.contains(spot.spot.id)
            }
        }
        return spotAggregator.spots.filter { spot in
            spot.spot.frequencyKHz >= band.lowerKHz
                && spot.spot.frequencyKHz <= band.upperKHz
                && selectedMode.matches(mode: spot.spot.mode)
                && enabledSources.contains(spot.spot.source)
                && enabledContinents.contains(spot.region.continent)
                && statusFilter.matches(status: spot.neededStatus, isWorkedToday: false)
                && !isExpired(spot)
        }
    }

    /// Bookmarks on the current band
    var bookmarksOnBand: [FrequencyBookmark] {
        bookmarks.filter { $0.bandId == selectedBandId }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                scopeHeader
                if filterMode != .widgets, let queryError = queryRunner.error {
                    sqlErrorBanner(queryError)
                }
                if filterMode != .widgets {
                    BandScopeCrossBandHints(
                        selectedBandId: $selectedBandId,
                        allowedSpotIDs: queryRunner.allowedSpotIDs,
                        spots: spotAggregator.spots
                    )
                }
                Divider()
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        miniMapRail(height: geo.size.height)
                            .onTapGesture { location in
                                handleMiniMapTap(
                                    at: location,
                                    railHeight: geo.size.height
                                )
                            }
                        Divider()
                        ZStack {
                            scopeCanvas(size: CGSize(
                                width: geo.size.width - Self.miniMapWidth - 1,
                                height: geo.size.height
                            ))
                            // Cursor crosshair
                            if let loc = cursorLocation {
                                cursorCrosshair(at: loc, size: CGSize(
                                    width: geo.size.width - Self.miniMapWidth - 1,
                                    height: geo.size.height
                                ))
                            }
                        }
                        .contentShape(Rectangle())
                        .onScrollWheel { event in
                            handleScrollWheel(event: event)
                        }
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                cursorLocation = location
                                if let band = selectedBand {
                                    cursorFreqKHz = freqForYPos(
                                        location.y, band: band,
                                        height: geo.size.height
                                    )
                                }
                            case .ended:
                                cursorLocation = nil
                                cursorFreqKHz = nil
                            }
                        }
                        .onTapGesture(count: 2) { location in
                            handleDoubleTap(at: location)
                        }
                        .onTapGesture { location in
                            handleTap(
                                at: location,
                                canvasHeight: geo.size.height
                            )
                        }
                        .contextMenu {
                            if let spot = hitRects.rects.first(where: {
                                guard let loc = cursorLocation else {
                                    return false
                                }
                                return $0.0.contains(loc)
                            })?.1 {
                                spotContextMenuActions(for: spot)
                            }
                        }
                        .gesture(panGesture(canvasHeight: geo.size.height))
                        .gesture(zoomGesture())
                    }
                }
                .frame(minWidth: 200, minHeight: 200)
                .background(.background.secondary)
                Divider()
                if showSummaryBar {
                    BandSummaryBar(
                        selectedBandId: selectedBandId,
                        enabledSources: enabledSources
                    )
                }
                scopeFooter
            }
            .focusable()
            .onKeyPress(phases: .down) { keyPress in
                handleKeyPress(keyPress)
            }
            .onChange(of: radioManager.frequency) { _, newFreq in
                autoSwitchBand(frequency: newFreq)
            }
            .task {
                await refreshSavedQueries()
                applyFilterMode()
            }
            .onChange(of: filterMode) { _, _ in
                applyFilterMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .savedQueriesChanged)) { _ in
                Task { await refreshSavedQueries() }
            }
            if showHelp {
                bandScopeHelpOverlay { showHelp = false }
            }
        }
    }

    // MARK: Private

    @State private var selectedMode: SpotModeFilter = .all
    @State private var enabledSources: Set<SpotSource> = Set(SpotSource.allCases)
    @State private var enabledContinents: Set<SpotContinent> = SpotContinent.allSet

    /// Cursor tracking
    @State private var cursorLocation: CGPoint?

    private func sqlErrorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.08))
    }

    private func refreshSavedQueries() async {
        guard let store = savedQueryStore else {
            return
        }
        let list = await (try? store.list()) ?? []
        savedQueries = list
        // Pre-validate column shape so the picker can grey out rows
        // that don't return spot_id. Cheap — column-name resolution
        // prepares without executing.
        var valid: Set<UUID> = []
        for query in list where await queryRunner.hasSpotIDColumn(sql: query.sql) {
            valid.insert(query.id)
        }
        validQueryIDs = valid
    }

    private func applyFilterMode() {
        switch filterMode {
        case .widgets:
            queryRunner.setQuery(nil)
        case let .savedQuery(uuid):
            Task {
                await refreshSavedQueries()
                if let query = savedQueries.first(where: { $0.id == uuid }) {
                    queryRunner.setQuery(query)
                } else {
                    filterMode = .widgets
                }
            }
        }
    }
}

// MARK: - Header & Footer

extension ContestBandScopeView {
    private var scopeHeader: some View {
        HStack(spacing: 8) {
            // Band picker is always visible — even in SQL mode the
            // user needs a way to choose which band's frequency
            // range the canvas renders. Mode is widget-only and
            // hides in SQL mode (the saved query has subsumed it).
            Picker("Band", selection: $selectedBandId) {
                ForEach(BandEdges.hfBands) { band in
                    Text(band.label).tag(band.id)
                }
            }
            .fixedSize()

            if filterMode == .widgets {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(SpotModeFilter.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .fixedSize()
            }

            filterModePicker

            Spacer()

            // Cursor frequency readout
            if let freq = cursorFreqKHz {
                HStack(spacing: 2) {
                    Text("cursor").font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.1f", freq))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .systemBlue))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color(nsColor: .systemBlue), lineWidth: 1)
                        )
                }
            }

            // VFO frequency readout
            HStack(spacing: 2) {
                Text("VFO").font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "%.1f", radioManager.frequency * 1_000))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color(nsColor: .systemRed), lineWidth: 1.5)
                    )
            }

            Text("\(spotsOnBand.count)")
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    /// Two-state mode picker. Saved queries that don't return a
    /// `spot_id` column are kept in the menu but rendered with a red
    /// "Missing spot_id" tag so the query name itself stays readable
    /// (a single grey block of greyed-out names was indistinguishable
    /// from a section header). Tapping a missing-spot_id row opens
    /// the Query Workbench preselected to that query so the user can
    /// fix it.
    private var filterModePicker: some View {
        Menu {
            Button("Widgets") { filterMode = .widgets }
            if !savedQueries.isEmpty {
                Divider()
                let usable = savedQueries.filter { validQueryIDs.contains($0.id) }
                let unusable = savedQueries.filter { !validQueryIDs.contains($0.id) }
                ForEach(usable) { query in
                    Button(query.name) { filterMode = .savedQuery(query.id) }
                }
                if !unusable.isEmpty {
                    Divider()
                    ForEach(unusable) { query in
                        Button {
                            openWindow(id: "query-workbench")
                        } label: {
                            Label(
                                "\(query.name)  —  ⚠ Missing spot_id (tap to fix)",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                        }
                    }
                }
                Divider()
                Button("Open Query Workbench…") {
                    openWindow(id: "query-workbench")
                }
            } else {
                Text("No saved queries — open the Query Workbench (⌘K → Open Query Workbench) to create one.")
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 3) {
                Text(filterModeLabel)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var filterModeLabel: String {
        switch filterMode {
        case .widgets:
            "Filter: Widgets"
        case let .savedQuery(uuid):
            if let query = savedQueries.first(where: { $0.id == uuid }) {
                "Query: \(query.name)"
            } else {
                "Query: (missing)"
            }
        }
    }

    private var scopeFooter: some View {
        HStack(spacing: 8) {
            Spacer()

            // Zoom controls
            HStack(spacing: 4) {
                Text("Zoom").font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "%.0f×", zoomScale))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)

                Button { adjustZoom(by: -0.5) } label: {
                    Text("−").font(.caption)
                }
                .buttonStyle(.borderless)

                Button { adjustZoom(by: 0.5) } label: {
                    Text("+").font(.caption)
                }
                .buttonStyle(.borderless)

                Button { resetZoom() } label: {
                    Text("FIT").font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.borderless)

                // Region presets for current band
                if let band = selectedBand {
                    let presets = ZoomRegionPreset.presets(for: band.id)
                    if !presets.isEmpty {
                        Menu {
                            ForEach(presets) { preset in
                                Button(preset.label) {
                                    zoomToRegion(preset)
                                }
                            }
                        } label: {
                            Text("Presets")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 50)
                    }
                }

                Divider().frame(height: 10)

                Button {
                    showHelp.toggle()
                } label: {
                    Text("?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(showHelp ? .primary : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Show keyboard shortcuts")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

// MARK: - Aging Helpers

extension ContestBandScopeView {
    private func ageFactor(for source: SpotSource) -> Double {
        switch source {
        case .rbn: 2.0
        case .cluster: 1.0
        case .pota,
             .sota,
             .wwff: 0.5
        case .dxSummit,
             .dxHeat,
             .dxWatch: 1.0
        }
    }

    private func effectiveAge(for spot: EnrichedSpot) -> Double {
        Date().timeIntervalSince(spot.spot.timestamp) * ageFactor(for: spot.spot.source)
    }

    func ageOpacity(for spot: EnrichedSpot) -> Double {
        let maxSeconds = Double(maxAgeMinutes) * 60
        return max(0.2, 1.0 - (effectiveAge(for: spot) / maxSeconds) * 0.8)
    }

    private func isExpired(_ spot: EnrichedSpot) -> Bool {
        effectiveAge(for: spot) > Double(maxAgeMinutes) * 60
    }
}
