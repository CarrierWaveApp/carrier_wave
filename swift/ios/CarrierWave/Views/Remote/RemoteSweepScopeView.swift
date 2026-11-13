import CarrierWaveCore
import SwiftUI

// MARK: - RemoteSweepScopeView

//
// Phone-shaped vertical band scope, modelled on CW Sweep's
// `ContestBandScopeView`: three-column layout (frequency axis | leader-line
// gutter | spot rows), pinch-to-zoom (1×–16×), drag-to-pan when zoomed,
// sub-band shading (CW/digital and SSB), spot displacement to avoid
// overlaps, age-based opacity, and tap-to-tune. Visual identity stays
// close to macOS so an operator carrying both knows the layout already.
//
// Drawing primitives, geometry, and helpers live in
// `RemoteSweepScopeView+Rendering.swift` to keep this file under SwiftLint's
// `type_body_length` cap.

struct RemoteSweepScopeView: View {
    // MARK: Internal

    struct ZoomState: Equatable {
        let zoom: CGFloat
        let pan: CGFloat
    }

    struct SpotRowLayout {
        let spot: RemoteSpot
        let axisY: CGFloat
        var rowY: CGFloat
    }

    // MARK: - Layout constants (mirror ContestBandScopeView)

    static let axisColumnWidth: CGFloat = 56
    static let gutterWidth: CGFloat = 36
    static let rowHeight: CGFloat = 22
    static let rowSpacing: CGFloat = 1

    static var rowsLeftEdge: CGFloat {
        axisColumnWidth + gutterWidth
    }

    // MARK: - State

    @Environment(RemoteSweepCoordinator.self) var coordinator
    @State var manualBand: String?

    /// Pinch + pan state. `panOffset` is the band-fraction at the centre of
    /// the visible viewport (0.5 = middle). `zoomScale = 1` shows the whole
    /// band; up to 16× zoom is allowed.
    @State var zoomScale: CGFloat = 1.0
    @State var zoomBaseScale: CGFloat = 1.0
    @State var panOffset: CGFloat = 0.5
    @State var panBaseOffset: CGFloat = 0.5
    @State var bandZoomStates: [String: ZoomState] = [:]

    @State var selectedSpotID: String?
    @State var hitRects: [(CGRect, RemoteSpot)] = []
    @State var detailSpot: RemoteSpot?

    // MARK: - Band selection

    var activeBand: String {
        if let manualBand {
            return manualBand
        }
        if let state = coordinator.radioState,
           let band = BandUtilities.deriveBand(from: Double(state.freqHz) / 1_000)
        {
            return band
        }
        return "20m"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()
            scope
        }
        .background(Color.black.opacity(0.95))
        .preferredColorScheme(.dark)
        .onChange(of: activeBand) { oldBand, newBand in
            saveZoomState(for: oldBand)
            applyZoomState(for: newBand)
        }
        .sheet(item: $detailSpot) { spot in
            RemoteSweepSpotDetailSheet(spot: spot)
                .environment(coordinator)
        }
    }

    func clampPan(_ value: CGFloat) -> CGFloat {
        let halfVisible = 0.5 / zoomScale
        return min(max(value, halfVisible), 1.0 - halfVisible)
    }

    func saveZoomState(for band: String) {
        bandZoomStates[band] = ZoomState(zoom: zoomScale, pan: panOffset)
    }

    func applyZoomState(for band: String) {
        if let state = bandZoomStates[band] {
            zoomScale = state.zoom
            zoomBaseScale = state.zoom
            panOffset = state.pan
            panBaseOffset = state.pan
        } else {
            resetZoom()
        }
    }

    func spotsForBand(_ band: String) -> [RemoteSpot] {
        coordinator.spots.filter { $0.band == band }
    }

    // MARK: Private

    private var filterLabel: String {
        switch coordinator.filterMode {
        case .widgets:
            "Filter: Widgets"
        case let .savedQuery(id):
            if let match = coordinator.savedQueries.first(where: { $0.id == id }) {
                "Filter: \(match.name)"
            } else {
                "Filter: (unknown)"
            }
        }
    }

    private var bandBinding: Binding<String> {
        Binding(
            get: { activeBand },
            set: { manualBand = $0 }
        )
    }

    private var visibleSpotsCount: Int {
        spotsForBand(activeBand).count
    }

    /// Sweep-side saved-query filter selector. Shown as a single line so it
    /// doesn't eat scope real estate when the operator isn't using SQL filters.
    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Menu {
                Button {
                    Task { await coordinator.setFilterMode(.widgets) }
                } label: {
                    Label("Widgets", systemImage: filterMatches(.widgets) ? "checkmark" : "")
                }
                if !coordinator.savedQueries.isEmpty {
                    Divider()
                    ForEach(coordinator.savedQueries) { query in
                        Button {
                            Task { await coordinator.setFilterMode(.savedQuery(query.id)) }
                        } label: {
                            HStack {
                                Image(systemName: filterMatches(.savedQuery(query.id)) ? "checkmark" : "")
                                Text(query.name)
                                if !query.drivesBandScope {
                                    Spacer()
                                    Text("(no spot_id)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(!query.drivesBandScope)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(filterLabel)
                        .font(.caption.bold())
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.cyan)
            }
            if coordinator.queriesLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.cyan)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Picker("Band", selection: bandBinding) {
                ForEach(BandUtilities.standardBands, id: \.self) { band in
                    Text(band).tag(band)
                }
            }
            .pickerStyle(.menu)
            .tint(.cyan)

            Spacer()

            Text("\(visibleSpotsCount) spots")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                resetZoom()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right.magnifyingglass")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(zoomScale <= 1.001)

            VStack(alignment: .trailing, spacing: 2) {
                if let state = coordinator.radioState {
                    Text(formatFrequency(state.freqHz))
                        .font(.system(.subheadline, design: .monospaced).bold())
                        .foregroundStyle(.cyan)
                    Text(state.mode)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No radio").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Scope canvas

    private var scope: some View {
        GeometryReader { proxy in
            let band = activeBand
            let range = BandUtilities.range(forBand: band) ?? (14.0, 14.35)
            let layouts = computeRowLayouts(
                spots: spotsForBand(band),
                range: range,
                height: proxy.size.height
            )

            ZStack {
                Canvas { context, size in
                    drawSubBandShading(context: context, size: size, band: band, range: range)
                    drawFrequencyAxis(context: context, size: size, range: range, layouts: layouts)
                    drawLeaderLines(context: context, layouts: layouts)
                    if let state = coordinator.radioState {
                        drawVFOCursor(
                            context: context,
                            size: size,
                            range: range,
                            freqHz: state.freqHz,
                            mode: state.mode
                        )
                    }
                    var capture: [(CGRect, RemoteSpot)] = []
                    drawSpotRows(
                        context: context,
                        size: size,
                        layouts: layouts,
                        selectedID: selectedSpotID,
                        rects: &capture
                    )
                    Task { @MainActor in hitRects = capture }
                }
                .contentShape(Rectangle())
                .gesture(panGesture(canvasHeight: proxy.size.height))
                .simultaneousGesture(zoomGesture())
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { event in
                            handleTap(at: event.location, in: proxy.size, range: range)
                        }
                )

                if coordinator.spotsLoading, coordinator.spots.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.cyan)
                        Text("Loading spots from Sweep…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func filterMatches(_ mode: RemoteFilterMode) -> Bool {
        switch (coordinator.filterMode, mode) {
        case (.widgets, .widgets): true
        case let (.savedQuery(a), .savedQuery(b)): a == b
        default: false
        }
    }

    // MARK: - Gestures

    private func panGesture(canvasHeight: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomScale > 1.0 else {
                    return
                }
                let dragFraction = value.translation.height / canvasHeight / zoomScale
                panOffset = clampPan(panBaseOffset - dragFraction)
            }
            .onEnded { _ in
                panBaseOffset = panOffset
                saveZoomState(for: activeBand)
            }
    }

    private func zoomGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoomScale = max(1.0, min(16.0, zoomBaseScale * value.magnification))
            }
            .onEnded { _ in
                zoomBaseScale = zoomScale
                panOffset = clampPan(panOffset)
                panBaseOffset = panOffset
                saveZoomState(for: activeBand)
            }
    }

    private func resetZoom() {
        zoomScale = 1.0
        zoomBaseScale = 1.0
        panOffset = 0.5
        panBaseOffset = 0.5
        saveZoomState(for: activeBand)
    }

    // MARK: - Tap handling

    private func handleTap(
        at location: CGPoint,
        in size: CGSize,
        range: (lowMHz: Double, highMHz: Double)
    ) {
        // Tapping a spot opens its detail sheet (operator confirms tune from
        // there). Tapping empty scope tunes Sweep to that frequency directly
        // — there's nothing to read in empty space.
        for (rect, spot) in hitRects where rect.contains(location) {
            selectedSpotID = spot.id
            detailSpot = spot
            return
        }
        let hz = freqHz(atY: location.y, in: size.height, range: range)
        selectedSpotID = nil
        Task { await coordinator.tune(freqHz: hz) }
    }

    // MARK: - Helpers

    private func formatFrequency(_ hz: UInt64) -> String {
        let mhz = Double(hz) / 1_000_000
        return String(format: "%.5f", mhz)
    }
}
