import CarrierWaveCore
import SwiftUI

// MARK: - BandMapView

/// Visual frequency band map showing spots as colored markers on a canvas
struct BandMapView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            bandCanvas
        }
    }

    // MARK: Private

    @Environment(SpotAggregator.self) private var spotAggregator
    @Environment(RadioManager.self) private var radioManager
    @State private var selectedBandId: String = "20m"
    @State private var selectedMode: SpotModeFilter = .all
    @AppStorage("autoXITEnabled") private var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") private var autoXITOffsetHz = 0
    @State private var hoveredSpot: EnrichedSpot?
    @State private var hitRects: [(CGRect, EnrichedSpot)] = []

    // MARK: - Canvas Drawing

    private let markerHeight: CGFloat = 16
    private let axisHeight: CGFloat = 20
    private let markerPadding: CGFloat = 2

    // MARK: - Canvas

    private var selectedBand: BandEdge? {
        BandEdges.hfBands.first { $0.id == selectedBandId }
    }

    private var spotsOnBand: [EnrichedSpot] {
        guard let band = selectedBand else {
            return []
        }
        return spotAggregator.spots.filter {
            $0.spot.frequencyKHz >= band.lowerKHz
                && $0.spot.frequencyKHz <= band.upperKHz
                && selectedMode.matches(mode: $0.spot.mode)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Band Map")
                .font(.headline)

            Spacer()

            // Mode filter
            Picker("Mode", selection: $selectedMode) {
                ForEach(SpotModeFilter.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            // Band selector
            Picker("Band", selection: $selectedBandId) {
                ForEach(BandEdges.hfBands) { band in
                    Text(band.label).tag(band.id)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 500)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var bandCanvas: some View {
        GeometryReader { geo in
            let size = geo.size
            let band = selectedBand

            ZStack {
                Canvas { context, canvasSize in
                    guard let band else {
                        return
                    }
                    drawSubBandShading(context: context, size: canvasSize, band: band)
                    let rects = drawSpotMarkers(context: context, size: canvasSize, band: band)
                    drawFrequencyCursor(context: context, size: canvasSize, band: band)
                    drawFrequencyAxis(context: context, size: canvasSize, band: band)

                    Task { @MainActor in
                        hitRects = rects
                    }
                }
                .accessibilityLabel("Band map showing \(spotsOnBand.count) spots on \(selectedBandId)")
                .accessibilityHint("Tap a spot to tune radio to that frequency")

                // Hover tooltip
                if let spot = hoveredSpot, let band {
                    let xFrac = BandEdges.xPosition(frequencyKHz: spot.spot.frequencyKHz, in: band)
                    let xPos = xFrac * size.width

                    tooltipView(for: spot)
                        .position(x: min(max(xPos, 80), size.width - 80), y: 20)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    hoveredSpot = hitRects.first { $0.0.contains(location) }?.1
                case .ended:
                    hoveredSpot = nil
                }
            }
            .onTapGesture { location in
                if let tapped = hitRects.first(where: { $0.0.contains(location) })?.1 {
                    Task {
                        try? await radioManager.tuneToFrequency(tapped.spot.frequencyMHz)
                        try? await radioManager.setMode(tapped.spot.mode)
                        if autoXITEnabled, autoXITOffsetHz != 0 {
                            try? await radioManager.setXITOffset(autoXITOffsetHz)
                            try? await radioManager.setXIT(true)
                        } else if autoXITEnabled {
                            try? await radioManager.setXIT(false)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 120)
        .background(.background.secondary)
        .onChange(of: radioManager.frequency) { _, newFreq in
            autoSwitchBand(frequency: newFreq)
        }
    }

    // MARK: - Tooltip

    private func tooltipView(for spot: EnrichedSpot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(spot.spot.callsign)
                .fontWeight(.bold)
            Text(String(format: "%.1f kHz", spot.spot.frequencyKHz))
                .monospacedDigit()
            if let ref = spot.spot.referenceDisplay {
                Text(ref)
                    .foregroundStyle(Color(nsColor: .systemGreen))
            }
            if let distBrg = spot.formattedDistanceAndBearing() {
                Text(distBrg)
            }
            Text(spot.spot.timeAgo)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func drawSubBandShading(context: GraphicsContext, size: CGSize, band: BandEdge) {
        let drawableHeight = size.height - axisHeight

        // CW segment
        if let digitalBoundary = band.digitalBoundaryKHz {
            let cwEnd = BandEdges.xPosition(frequencyKHz: digitalBoundary, in: band) * size.width
            let cwRect = CGRect(x: 0, y: 0, width: cwEnd, height: drawableHeight)
            context.fill(Path(cwRect), with: .color(.blue.opacity(0.05)))
        }

        // SSB segment
        if let ssbBoundary = band.ssbBoundaryKHz {
            let ssbStart = BandEdges.xPosition(frequencyKHz: ssbBoundary, in: band) * size.width
            let ssbRect = CGRect(x: ssbStart, y: 0, width: size.width - ssbStart, height: drawableHeight)
            context.fill(Path(ssbRect), with: .color(.orange.opacity(0.05)))
        }
    }

    private func drawSpotMarkers(
        context: GraphicsContext,
        size: CGSize,
        band: BandEdge
    ) -> [(CGRect, EnrichedSpot)] {
        let drawableHeight = size.height - axisHeight
        var rects: [(CGRect, EnrichedSpot)] = []

        // Group spots into vertical lanes to avoid overlap
        var lanes: [[EnrichedSpot]] = []

        for spot in spotsOnBand {
            let xFrac = BandEdges.xPosition(frequencyKHz: spot.spot.frequencyKHz, in: band)
            let xPos = xFrac * size.width

            // Find a lane where this spot doesn't overlap
            var placed = false
            for i in lanes.indices {
                let overlaps = lanes[i].contains { existing in
                    let existingX = BandEdges.xPosition(
                        frequencyKHz: existing.spot.frequencyKHz, in: band
                    ) * size.width
                    return abs(xPos - existingX) < 60
                }
                if !overlaps {
                    lanes[i].append(spot)
                    placed = true
                    break
                }
            }
            if !placed {
                lanes.append([spot])
            }
        }

        // Draw each lane
        for (laneIndex, lane) in lanes.enumerated() {
            let y = CGFloat(laneIndex) * (markerHeight + markerPadding) + markerPadding
            guard y + markerHeight < drawableHeight else {
                continue
            }

            for spot in lane {
                let xFrac = BandEdges.xPosition(frequencyKHz: spot.spot.frequencyKHz, in: band)
                let xPos = xFrac * size.width

                // Opacity based on age (1.0 → 0.3 over 30 min)
                let ageSeconds = Date().timeIntervalSince(spot.spot.timestamp)
                let opacity = max(0.3, 1.0 - (ageSeconds / 1_800) * 0.7)

                let color = markerColor(for: spot.spot.source)
                let label = spot.spot.callsign
                let labelWidth: CGFloat = 56
                let rect = CGRect(
                    x: xPos - labelWidth / 2,
                    y: y,
                    width: labelWidth,
                    height: markerHeight
                )

                // Background chip
                let chipPath = Path(roundedRect: rect, cornerRadius: 3)
                context.fill(chipPath, with: .color(color.opacity(opacity * 0.3)))
                context.stroke(chipPath, with: .color(color.opacity(opacity)), lineWidth: 0.5)

                // Label text
                let text = Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(color.opacity(opacity))
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: xPos, y: y + markerHeight / 2),
                    anchor: .center
                )

                rects.append((rect, spot))
            }
        }

        return rects
    }

    private func drawFrequencyCursor(context: GraphicsContext, size: CGSize, band: BandEdge) {
        let radioFreqKHz = radioManager.frequency * 1_000
        guard radioFreqKHz >= band.lowerKHz, radioFreqKHz <= band.upperKHz else {
            return
        }

        let xFrac = BandEdges.xPosition(frequencyKHz: radioFreqKHz, in: band)
        let xPos = xFrac * size.width
        let drawableHeight = size.height - axisHeight

        var cursorPath = Path()
        cursorPath.move(to: CGPoint(x: xPos, y: 0))
        cursorPath.addLine(to: CGPoint(x: xPos, y: drawableHeight))
        context.stroke(cursorPath, with: .color(Color(nsColor: .systemRed).opacity(0.8)), lineWidth: 1.5)
    }

    private func drawFrequencyAxis(context: GraphicsContext, size: CGSize, band: BandEdge) {
        let axisY = size.height - axisHeight

        // Axis line
        var linePath = Path()
        linePath.move(to: CGPoint(x: 0, y: axisY))
        linePath.addLine(to: CGPoint(x: size.width, y: axisY))
        context.stroke(linePath, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

        // Tick marks and labels
        let stepKHz = axisStep(for: band)
        var freq = (band.lowerKHz / stepKHz).rounded(.up) * stepKHz

        while freq <= band.upperKHz {
            let xFrac = BandEdges.xPosition(frequencyKHz: freq, in: band)
            let xPos = xFrac * size.width

            var tickPath = Path()
            tickPath.move(to: CGPoint(x: xPos, y: axisY))
            tickPath.addLine(to: CGPoint(x: xPos, y: axisY + 4))
            context.stroke(tickPath, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)

            let label = Text(String(format: "%.0f", freq))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            context.draw(
                context.resolve(label),
                at: CGPoint(x: xPos, y: axisY + 12),
                anchor: .center
            )

            freq += stepKHz
        }
    }

    private func axisStep(for band: BandEdge) -> Double {
        let width = band.widthKHz
        if width > 1_000 {
            return 200
        }
        if width > 200 {
            return 50
        }
        if width > 50 {
            return 10
        }
        return 5
    }

    // MARK: - Helpers

    private func markerColor(for source: SpotSource) -> Color {
        switch source {
        case .rbn: Color(nsColor: .systemBlue)
        case .pota: Color(nsColor: .systemGreen)
        case .sota: Color(nsColor: .systemOrange)
        case .wwff: Color(nsColor: .systemTeal)
        case .cluster: Color(nsColor: .systemYellow)
        }
    }

    private func autoSwitchBand(frequency freqMHz: Double) {
        let freqKHz = freqMHz * 1_000
        if let band = BandEdges.band(for: freqKHz) {
            selectedBandId = band.id
        }
    }
}

// MARK: - BandMapPanel

/// Standalone band map window
struct BandMapPanel: View {
    var body: some View {
        BandMapView()
            .frame(minWidth: 400, minHeight: 300)
    }
}
