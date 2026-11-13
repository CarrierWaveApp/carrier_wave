import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - BandMapView

/// Visual frequency band map showing spots as colored markers on a canvas.
/// Supports zoom/pan via scroll+pinch, spot selection via SelectionState,
/// and compact header with dropdown band picker.
struct BandMapView: View {
    // MARK: Internal

    @Environment(SpotAggregator.self) var spotAggregator
    @Environment(RadioManager.self) var radioManager
    @Environment(SelectionState.self) var selectionState
    @State var selectedBandId: String = "20m"

    /// Zoom level (1.0 = full band, higher = zoomed in)
    @State var zoomScale: CGFloat = 1.0
    /// Base zoom for pinch gesture (snapshot at gesture start)
    @State var zoomBaseScale: CGFloat = 1.0
    /// Pan center as fraction of band width (0.5 = centered)
    @State var panOffset: CGFloat = 0.5
    /// Base pan for drag gesture (snapshot at gesture start)
    @State var panBaseOffset: CGFloat = 0.5

    @AppStorage("bandScopeColorMode") var colorMode: BandScopeColorMode = .source
    /// Operator callsign — own spots get an accent ring/bar (see `drawSpotChip`).
    @AppStorage("myCallsign") var myCallsign = ""
    @AppStorage("bandScopeMaxAgeMinutes") var maxAgeMinutes: Int = 30
    @AppStorage("bandScopeStatusFilter") var statusFilter: SpotStatusFilter = .all
    @AppStorage("bandScopeFilterMode") var filterMode: BandScopeFilterMode = .widgets
    @State var enabledSources: Set<SpotSource> = Set(SpotSource.allCases)
    @State var enabledContinents: Set<SpotContinent> = SpotContinent.allSet
    @State var isFilterExpanded: Bool = false
    @Environment(BandScopeQueryRunner.self) var queryRunner
    @State var savedQueries: [SavedQuery] = []
    @State var validQueryIDs: Set<UUID> = []
    @Environment(\.savedQueryStore) var savedQueryStore

    let markerHeight: CGFloat = 16
    let prominentMarkerHeight: CGFloat = 20
    let axisHeight: CGFloat = 24
    let markerPadding: CGFloat = 2
    let chipPaddingH: CGFloat = 6

    var spotsOnBand: [EnrichedSpot] {
        guard let band = selectedBand else {
            return []
        }
        // SQL-driven filter mode: trust the query's allow-list. We still
        // clip to the visible band so the canvas isn't asked to draw
        // off-axis spots, but skip the widget filters entirely. If the
        // runner has no allow-list yet (loading or query failed), we
        // fall back to widget filters so the scope is never blank.
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
                && !isExpired(spot)
                && enabledSources.contains(spot.spot.source)
                && enabledContinents.contains(spot.region.continent)
                && statusFilter.matches(status: spot.neededStatus, isWorkedToday: false)
        }
    }

    var prioritizedSpots: [EnrichedSpot] {
        spotsOnBand.sorted { spotPriority($0) > spotPriority($1) }
    }

    var selectedBand: BandEdge? {
        BandEdges.hfBands.first { $0.id == selectedBandId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            BandScopeFilterBar(
                enabledSources: $enabledSources,
                statusFilter: $statusFilter,
                enabledContinents: $enabledContinents,
                isExpanded: $isFilterExpanded,
                filterMode: $filterMode,
                savedQueries: savedQueries,
                validQueryIDs: validQueryIDs,
                queryError: queryRunner.error
            )
            if filterMode != .widgets {
                BandScopeCrossBandHints(
                    selectedBandId: $selectedBandId,
                    allowedSpotIDs: queryRunner.allowedSpotIDs,
                    spots: spotAggregator.spots
                )
            }
            Divider()
            bandCanvas
            Divider()
            BandSummaryBar(selectedBandId: selectedBandId, enabledSources: enabledSources)
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
    }

    // MARK: Private

    @State private var selectedMode: SpotModeFilter = .all
    @AppStorage("autoXITEnabled") private var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") private var autoXITOffsetHz = 0
    @State private var hoveredSpot: EnrichedSpot?
    /// Written by the Canvas on each draw; see `SpotHitRects` for why it isn't `@State` data.
    @State private var hitRects = SpotHitRects()

    /// Reload the saved-query list from the actor-backed store and
    /// classify which queries can drive the band scope by checking
    /// each statement's column shape.
    private func refreshSavedQueries() async {
        guard let store = savedQueryStore else {
            return
        }
        let list = await (try? store.list()) ?? []
        savedQueries = list
        var valid: Set<UUID> = []
        for query in list where await queryRunner.hasSpotIDColumn(sql: query.sql) {
            valid.insert(query.id)
        }
        validQueryIDs = valid
    }

    /// React to a mode change by either tearing down the SQL filter
    /// (widgets) or reloading queries and pointing the runner at the
    /// newly-picked one.
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
                    // The persisted UUID doesn't resolve — likely the
                    // saved query was deleted. Drop back to widgets.
                    filterMode = .widgets
                }
            }
        }
    }
}

// MARK: - Header

extension BandMapView {
    var header: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: $selectedMode) {
                ForEach(SpotModeFilter.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Divider().frame(height: 16)

            Picker("Band", selection: $selectedBandId) {
                ForEach(BandEdges.hfBands) { band in
                    Text(band.label).tag(band.id)
                }
            }
            .frame(width: 70)

            Divider().frame(height: 16)

            colorModePicker

            Spacer()

            ageLabel

            if zoomScale > 1.01 {
                Text(String(format: "%.0fx", zoomScale))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var colorModePicker: some View {
        Menu {
            ForEach(BandScopeColorMode.allCases) { mode in
                Button {
                    colorMode = mode
                } label: {
                    Label(mode.displayName, systemImage: mode.icon)
                }
            }
        } label: {
            Label(colorMode.displayName, systemImage: colorMode.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 90)
    }

    private var ageLabel: some View {
        Menu {
            ForEach([10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) min") {
                    maxAgeMinutes = minutes
                }
            }
        } label: {
            Text("\(maxAgeMinutes)m")
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 36)
        .help("Spot decay time")
    }
}

// MARK: - Canvas

extension BandMapView {
    var bandCanvas: some View {
        GeometryReader { geo in
            let size = geo.size
            let band = selectedBand
            ZStack {
                Canvas { context, canvasSize in
                    guard let band else {
                        return
                    }
                    drawSubBandShading(context: context, size: canvasSize, band: band)
                    drawProximityZone(context: context, size: canvasSize, band: band)
                    let rects = drawSpotMarkers(context: context, size: canvasSize, band: band)
                    drawSelectedSpotIndicator(context: context, size: canvasSize, band: band)
                    drawFrequencyCursor(context: context, size: canvasSize, band: band)
                    drawFrequencyAxis(context: context, size: canvasSize, band: band)
                    Task { @MainActor in hitRects.rects = rects }
                }
                .accessibilityLabel("Band map: \(spotsOnBand.count) spots on \(selectedBandId)")

                if let spot = hoveredSpot, let band {
                    let xPos = zoomedXPosition(
                        frequencyKHz: spot.spot.frequencyKHz,
                        band: band, width: size.width
                    )
                    tooltipView(for: spot)
                        .position(x: min(max(xPos, 80), size.width - 80), y: 20)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    hoveredSpot = hitRects.spot(at: location)
                case .ended:
                    hoveredSpot = nil
                }
            }
            .onTapGesture { location in
                handleTap(at: location)
            }
            .gesture(panGesture(canvasWidth: size.width))
            .gesture(scrollZoomGesture(canvasWidth: size.width))
        }
        .frame(minHeight: 120)
        .background(.background.secondary)
        .onChange(of: radioManager.frequency) { _, newFreq in
            autoSwitchBand(frequency: newFreq)
        }
        .onChange(of: selectionState.selectedSpot?.id) { _, newId in
            scrollToSelectedSpot(spotId: newId)
        }
    }

    private func handleTap(at location: CGPoint) {
        guard let tapped = hitRects.spot(at: location) else {
            return
        }
        SpotEntryBridge.shared.pendingSpot = tapped
        selectionState.selectedSpot = tapped
        selectionState.selectedQSOId = nil
        Task {
            await radioManager.tuneToSpot(
                frequencyMHz: tapped.spot.frequencyMHz,
                mode: tapped.spot.mode,
                autoXITEnabled: autoXITEnabled,
                autoXITOffsetHz: autoXITOffsetHz
            )
        }
    }

    private func scrollToSelectedSpot(spotId: String?) {
        guard let spotId,
              let spot = spotAggregator.spots.first(where: { $0.id == spotId })
        else {
            return
        }
        let freqKHz = spot.spot.frequencyKHz
        // Switch band if the spot is on a different one
        if let targetBand = BandEdges.band(for: freqKHz), targetBand.id != selectedBandId {
            selectedBandId = targetBand.id
        }
        // Pan to center the spot when zoomed
        guard zoomScale > 1.0, let currentBand = selectedBand else {
            return
        }
        let frac = BandEdges.xPosition(frequencyKHz: freqKHz, in: currentBand)
        withAnimation(.easeInOut(duration: 0.3)) {
            panOffset = clampPan(frac)
        }
    }

    /// Drag to pan when zoomed
    private func panGesture(canvasWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > 1.0 else {
                    return
                }
                let dragFraction = value.translation.width / canvasWidth / zoomScale
                panOffset = clampPan(panBaseOffset - dragFraction)
            }
            .onEnded { _ in
                panBaseOffset = panOffset
            }
    }

    /// Pinch to zoom
    private func scrollZoomGesture(canvasWidth: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoomScale = max(1.0, min(16.0, zoomBaseScale * value.magnification))
            }
            .onEnded { _ in
                zoomBaseScale = zoomScale
                panOffset = clampPan(panOffset)
                panBaseOffset = panOffset
            }
    }
}

// MARK: - Zoom Helpers

extension BandMapView {
    func zoomedXPosition(frequencyKHz: Double, band: BandEdge, width: CGFloat) -> CGFloat {
        let frac = BandEdges.xPosition(frequencyKHz: frequencyKHz, in: band)
        let visibleWidth = 1.0 / zoomScale
        let visibleStart = panOffset - visibleWidth / 2
        let normalizedX = (frac - visibleStart) / visibleWidth
        return normalizedX * width
    }

    func clampPan(_ value: CGFloat) -> CGFloat {
        let halfVisible = 0.5 / zoomScale
        return min(max(value, halfVisible), 1.0 - halfVisible)
    }
}

// MARK: - Tooltip

extension BandMapView {
    func tooltipView(for spot: EnrichedSpot) -> some View {
        SpotTooltipView(spot: spot)
    }
}

// MARK: - SpotTooltipView

/// Tooltip popover showing detailed spot information on hover.
struct SpotTooltipView: View {
    // MARK: Internal

    let spot: EnrichedSpot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            headerRow
            statusRow
            frequencyRow
            detailRows
            Divider()
            footerRow
        }
        .font(.caption)
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Private

    private var headerRow: some View {
        HStack(spacing: 4) {
            Text(spot.spot.callsign)
                .fontWeight(.bold)
                .foregroundStyle(SpotColorScheme.neededColor(spot.neededStatus))
            Text(spot.spot.source.displayName)
                .font(.system(size: 8, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    SpotColorScheme.sourceColor(spot.spot.source).opacity(0.3),
                    in: Capsule()
                )
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if spot.neededStatus != .unknown {
            Text(spot.neededStatus.label)
                .font(.caption2.bold())
                .foregroundStyle(SpotColorScheme.neededColor(spot.neededStatus))
        }
    }

    private var frequencyRow: some View {
        HStack(spacing: 4) {
            Text(String(format: "%.1f kHz", spot.spot.frequencyKHz))
                .monospacedDigit()
            if !spot.spot.mode.isEmpty {
                Text(spot.spot.mode).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detailRows: some View {
        if let entity = spot.dxccEntity {
            Text(entity).foregroundStyle(.secondary)
        }
        if let ref = spot.spot.referenceDisplay {
            Text(ref).foregroundStyle(Color(nsColor: .systemGreen))
        }
        if let snr = spot.spot.snr {
            HStack(spacing: 4) {
                Text("\(snr) dB").monospacedDigit()
                if let wpm = spot.spot.wpm {
                    Text("\(wpm) wpm").monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
        }
        if spot.spot.lotwUser == true {
            Text("LoTW")
                .font(.caption2.bold())
                .foregroundStyle(Color(nsColor: .systemGreen))
        }
        if let distBrg = spot.formattedDistanceAndBearing() {
            Text(distBrg)
        }
    }

    private var footerRow: some View {
        HStack(spacing: 4) {
            if let spotter = spot.spot.spotter {
                Text("by \(spotter)").foregroundStyle(.tertiary)
            }
            Spacer()
            Text(spot.spot.timeAgo).foregroundStyle(.secondary)
        }
    }
}

// MARK: - BandMapPanel

struct BandMapPanel: View {
    var body: some View {
        BandMapView()
            .frame(minWidth: 400, minHeight: 300)
    }
}
