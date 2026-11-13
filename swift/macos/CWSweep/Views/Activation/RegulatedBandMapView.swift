import CarrierWaveCore
import SwiftUI

// MARK: - RegulatedBandMapView

/// Two-tier band map with operator class privilege enforcement, spot overlay, and click-to-tune
struct RegulatedBandMapView: View {
    // MARK: Internal

    @Environment(SpotAggregator.self) var spotAggregator
    @Environment(RadioManager.self) var radioManager

    @State var selectedBandId: String = "20m"
    @State var zoomCenter: Double?
    @State var zoomScale: CGFloat = 1.0
    @State var hoveredSpot: EnrichedSpot?

    let overviewHeight: CGFloat = 50
    let zoomedHeight: CGFloat = 160
    let axisHeight: CGFloat = 20
    let pillHeight: CGFloat = 28

    var selectedBand: BandEdge? {
        BandEdges.hfBands.first { $0.id == selectedBandId }
    }

    var spotsOnBand: [EnrichedSpot] {
        guard let band = selectedBand else {
            return []
        }
        return spotAggregator.spots.filter {
            $0.spot.frequencyKHz >= band.lowerKHz
                && $0.spot.frequencyKHz <= band.upperKHz
        }
    }

    var bandSegmentsOnBand: [BandSegment] {
        guard let band = selectedBand else {
            return []
        }
        let lowerMHz = band.lowerKHz / 1_000
        let upperMHz = band.upperKHz / 1_000
        return BandPlan.segments.filter { seg in
            seg.band == band.id && seg.endMHz >= lowerMHz && seg.startMHz <= upperMHz
        }
    }

    /// Effective zoom center: follows VFO when nil
    var effectiveZoomCenter: Double {
        if let zoomCenter {
            return zoomCenter
        }
        return radioManager.frequency * 1_000 // MHz -> kHz
    }

    /// Half-width of zoom window in kHz
    var zoomHalfWidth: Double {
        12.5 / Double(zoomScale) // ~25 kHz at 1x zoom
    }

    var userLicense: LicenseClass {
        LicenseClass(rawValue: licenseClass) ?? .general
    }

    var body: some View {
        VStack(spacing: 0) {
            overviewCanvas
            Divider()
            zoomedCanvas
            Divider()
            bandPills
        }
        .onChange(of: radioManager.frequency) { _, newFreq in
            autoSwitchBand(frequency: newFreq)
        }
    }

    // MARK: Private

    @AppStorage("licenseClass") private var licenseClass = "General"
    @AppStorage("autoXITEnabled") private var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") private var autoXITOffsetHz = 0
    /// Written by the Canvas on each draw; see `SpotHitRects` for why it isn't `@State` data.
    @State private var hitRects = SpotHitRects()
    @State private var privilegeWarning: String?
    @State private var warningTask: Task<Void, Never>?

    // MARK: - Overview Strip

    private var overviewCanvas: some View {
        Canvas { context, size in
            guard let band = selectedBand else {
                return
            }
            drawOverviewStrip(
                context: context, size: size, band: band,
                segments: bandSegmentsOnBand, license: userLicense
            )
        }
        .frame(height: overviewHeight)
        .accessibilityLabel("Band overview for \(selectedBandId)")
    }

    // MARK: - Zoomed View

    private var zoomedCanvas: some View {
        GeometryReader { geo in
            let size = geo.size
            let band = selectedBand
            ZStack {
                Canvas { context, canvasSize in
                    guard let band else {
                        return
                    }
                    let rects = drawZoomedView(
                        context: context, size: canvasSize, band: band,
                        spots: spotsOnBand, license: userLicense
                    )
                    Task { @MainActor in hitRects.rects = rects }
                }
                .accessibilityLabel("Zoomed band map with \(spotsOnBand.count) spots")

                if let spot = hoveredSpot, let band {
                    zoomTooltip(for: spot, band: band, size: size)
                }

                if let warning = privilegeWarning {
                    privilegeWarningOverlay(warning)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                handleHover(phase: phase)
            }
            .onTapGesture { location in
                handleTap(at: location, canvasWidth: size.width)
            }
            .onScrollWheel { event in
                handleScrollWheel(delta: event.deltaY)
            }
        }
        .frame(height: zoomedHeight)
        .background(.background.secondary)
    }

    // MARK: - Band Pills

    private var bandPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BandEdges.hfBands) { band in
                    bandPill(for: band)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: pillHeight + 8)
    }

    private func bandPill(for band: BandEdge) -> some View {
        let isSelected = band.id == selectedBandId
        return Text(band.label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .onTapGesture { selectedBandId = band.id }
    }

    // MARK: - Tooltip

    private func zoomTooltip(
        for spot: EnrichedSpot, band: BandEdge, size: CGSize
    ) -> some View {
        let zoomLower = effectiveZoomCenter - zoomHalfWidth
        let zoomWidth = zoomHalfWidth * 2
        let xFrac = (spot.spot.frequencyKHz - zoomLower) / zoomWidth
        let xPos = xFrac * size.width
        return spotTooltipView(for: spot)
            .position(
                x: min(max(xPos, 80), size.width - 80),
                y: 20
            )
    }

    private func spotTooltipView(for spot: EnrichedSpot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(spot.spot.callsign).fontWeight(.bold)
            Text(String(format: "%.1f kHz", spot.spot.frequencyKHz))
                .monospacedDigit()
            if let entity = spot.dxccEntity {
                Text(entity).foregroundStyle(.secondary)
            }
            if let ref = spot.spot.referenceDisplay {
                Text(ref).foregroundStyle(Color(nsColor: .systemGreen))
            }
            Text(spot.spot.timeAgo).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func privilegeWarningOverlay(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.85), in: Capsule())
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: privilegeWarning)
    }
}

// MARK: - RegulatedBandMapView + Interactions

extension RegulatedBandMapView {
    func autoSwitchBand(frequency freqMHz: Double) {
        let freqKHz = freqMHz * 1_000
        if let band = BandEdges.band(for: freqKHz) {
            selectedBandId = band.id
        }
    }

    func handleHover(phase: HoverPhase) {
        switch phase {
        case let .active(location):
            hoveredSpot = hitRects.spot(at: location)
        case .ended:
            hoveredSpot = nil
        }
    }

    func handleTap(at location: CGPoint, canvasWidth: CGFloat) {
        // Check if tapping a spot
        if let tapped = hitRects.spot(at: location) {
            tuneToSpot(tapped)
            return
        }
        // Click empty space -> tune to that frequency
        guard let band = selectedBand else {
            return
        }
        let zoomLower = effectiveZoomCenter - zoomHalfWidth
        let zoomWidth = zoomHalfWidth * 2
        let freqKHz = zoomLower + (location.x / canvasWidth) * zoomWidth
        let freqMHz = freqKHz / 1_000

        if isExtraOnly(frequencyMHz: freqMHz, band: band), userLicense != .extra {
            showPrivilegeWarning("Extra class only")
            return
        }
        Task {
            await radioManager.tuneToSpot(
                frequencyMHz: freqMHz, mode: radioManager.mode,
                autoXITEnabled: autoXITEnabled,
                autoXITOffsetHz: autoXITOffsetHz
            )
        }
    }

    func handleScrollWheel(delta: CGFloat) {
        let newScale = max(0.5, min(4.0, zoomScale + delta * 0.1))
        zoomScale = newScale
    }

    func tuneToSpot(_ spot: EnrichedSpot) {
        guard let band = selectedBand else {
            return
        }
        let freqMHz = spot.spot.frequencyMHz
        if isExtraOnly(frequencyMHz: freqMHz, band: band), userLicense != .extra {
            showPrivilegeWarning("Extra class only")
            return
        }
        Task {
            await radioManager.tuneToSpot(
                frequencyMHz: freqMHz, mode: spot.spot.mode,
                autoXITEnabled: autoXITEnabled,
                autoXITOffsetHz: autoXITOffsetHz
            )
        }
    }

    func isExtraOnly(frequencyMHz: Double, band: BandEdge) -> Bool {
        let segs = BandPlan.segments.filter { seg in
            seg.band == band.id && seg.contains(frequencyMHz: frequencyMHz)
        }
        // If the only segments covering this frequency require Extra
        let nonExtra = segs.filter { $0.minimumLicense != .extra }
        return !segs.isEmpty && nonExtra.isEmpty
    }

    func showPrivilegeWarning(_ text: String) {
        warningTask?.cancel()
        privilegeWarning = text
        warningTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            privilegeWarning = nil
        }
    }
}

// ScrollWheelModifier moved to Utilities/ScrollWheelModifier.swift
