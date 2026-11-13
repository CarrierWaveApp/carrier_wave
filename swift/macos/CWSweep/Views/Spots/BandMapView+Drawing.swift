import CarrierWaveCore
import SwiftUI

// MARK: - BandMapView + Drawing

extension BandMapView {
    // MARK: - Sub-Band Shading

    func drawSubBandShading(context: GraphicsContext, size: CGSize, band: BandEdge) {
        let drawableHeight = size.height - axisHeight

        if let digitalBoundary = band.digitalBoundaryKHz {
            let cwEnd = zoomedXPosition(frequencyKHz: digitalBoundary, band: band, width: size.width)
            let cwRect = CGRect(x: 0, y: 0, width: cwEnd, height: drawableHeight)
            context.fill(Path(cwRect), with: .color(.blue.opacity(0.05)))
        }

        if let ssbBoundary = band.ssbBoundaryKHz {
            let ssbStart = zoomedXPosition(frequencyKHz: ssbBoundary, band: band, width: size.width)
            let ssbRect = CGRect(
                x: ssbStart, y: 0,
                width: size.width - ssbStart, height: drawableHeight
            )
            context.fill(Path(ssbRect), with: .color(.orange.opacity(0.05)))
        }
    }

    // MARK: - Proximity Zone

    func drawProximityZone(context: GraphicsContext, size: CGSize, band: BandEdge) {
        let radioFreqKHz = radioManager.frequency * 1_000
        guard radioFreqKHz >= band.lowerKHz, radioFreqKHz <= band.upperKHz else {
            return
        }

        let halfWidth = proximityHalfWidthKHz()
        let leftX = zoomedXPosition(
            frequencyKHz: max(radioFreqKHz - halfWidth, band.lowerKHz),
            band: band, width: size.width
        )
        let rightX = zoomedXPosition(
            frequencyKHz: min(radioFreqKHz + halfWidth, band.upperKHz),
            band: band, width: size.width
        )
        let drawableHeight = size.height - axisHeight
        let zoneRect = CGRect(x: leftX, y: 0, width: rightX - leftX, height: drawableHeight)
        context.fill(Path(zoneRect), with: .color(.white.opacity(0.04)))
    }

    // MARK: - Spot Markers

    func drawSpotMarkers(
        context: GraphicsContext,
        size: CGSize,
        band: BandEdge
    ) -> [(CGRect, EnrichedSpot)] {
        var context = context
        let drawableHeight = size.height - axisHeight
        var rects: [(CGRect, EnrichedSpot)] = []

        let resolved = resolveSpotLabels(context: &context, band: band, size: size)
        let maxLanes = max(1, Int((drawableHeight - markerPadding) / (prominentMarkerHeight + markerPadding)))
        let lanes = assignLanes(resolved: resolved, maxLanes: maxLanes)

        for (laneIndex, lane) in lanes.enumerated() {
            let yOffset = CGFloat(laneIndex) * (prominentMarkerHeight + markerPadding) + markerPadding
            for item in lane {
                drawSpotChip(
                    item: item, yOffset: yOffset,
                    context: &context, rects: &rects
                )
            }
        }

        return rects
    }

    // MARK: - Selected Spot Indicator

    func drawSelectedSpotIndicator(context: GraphicsContext, size: CGSize, band: BandEdge) {
        guard let selectedSpot = selectionState.selectedSpot else {
            return
        }
        let freqKHz = selectedSpot.spot.frequencyKHz
        guard freqKHz >= band.lowerKHz, freqKHz <= band.upperKHz else {
            return
        }

        let xPos = zoomedXPosition(frequencyKHz: freqKHz, band: band, width: size.width)
        let drawableHeight = size.height - axisHeight

        // Dashed vertical line
        var linePath = Path()
        linePath.move(to: CGPoint(x: xPos, y: 0))
        linePath.addLine(to: CGPoint(x: xPos, y: drawableHeight))
        context.stroke(
            linePath,
            with: .color(Color(nsColor: .systemYellow).opacity(0.7)),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )

        // Frequency label at top
        let label = Text(String(format: "%.1f", freqKHz))
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(nsColor: .systemYellow))
        let resolved = context.resolve(label)
        let labelSize = resolved.measure(in: CGSize(width: 200, height: 20))

        let pillRect = CGRect(
            x: xPos - labelSize.width / 2 - 3,
            y: drawableHeight - 16,
            width: labelSize.width + 6,
            height: 14
        )
        context.fill(
            Path(roundedRect: pillRect, cornerRadius: 3),
            with: .color(.black.opacity(0.75))
        )
        context.draw(resolved, at: CGPoint(x: xPos, y: drawableHeight - 9), anchor: .center)
    }

    // MARK: - Frequency Cursor

    /// Estimated IF filter half-width in kHz based on current radio mode.
    /// Used for passband shading until real filter width CAT commands are wired.
    func estimatedFilterHalfWidthKHz() -> Double {
        let radioMode = radioManager.mode
        let family = ModeEquivalence.family(for: radioMode)
        switch family {
        case .cw: return 0.25 // ~500 Hz filter
        case .digital: return 1.5 // ~3 kHz filter
        case .phone: return 1.2 // ~2.4 kHz filter
        case .other: return 1.5
        }
    }

    func drawFrequencyCursor(context: GraphicsContext, size: CGSize, band: BandEdge) {
        let radioFreqKHz = radioManager.frequency * 1_000
        guard radioFreqKHz >= band.lowerKHz, radioFreqKHz <= band.upperKHz else {
            return
        }

        let xPos = zoomedXPosition(frequencyKHz: radioFreqKHz, band: band, width: size.width)
        let drawableHeight = size.height - axisHeight

        // Filter width shading (estimated passband)
        let filterHalf = estimatedFilterHalfWidthKHz()
        let filterLeft = zoomedXPosition(
            frequencyKHz: max(radioFreqKHz - filterHalf, band.lowerKHz),
            band: band, width: size.width
        )
        let filterRight = zoomedXPosition(
            frequencyKHz: min(radioFreqKHz + filterHalf, band.upperKHz),
            band: band, width: size.width
        )
        let filterRect = CGRect(
            x: filterLeft, y: 0,
            width: filterRight - filterLeft, height: drawableHeight
        )
        context.fill(
            Path(filterRect),
            with: .color(Color(nsColor: .systemBlue).opacity(0.08))
        )

        // Glow
        var glowPath = Path()
        glowPath.move(to: CGPoint(x: xPos, y: 0))
        glowPath.addLine(to: CGPoint(x: xPos, y: drawableHeight))
        context.stroke(glowPath, with: .color(Color(nsColor: .systemRed).opacity(0.25)), lineWidth: 6)

        // Cursor line
        var cursorPath = Path()
        cursorPath.move(to: CGPoint(x: xPos, y: 0))
        cursorPath.addLine(to: CGPoint(x: xPos, y: drawableHeight))
        context.stroke(cursorPath, with: .color(Color(nsColor: .systemRed).opacity(0.9)), lineWidth: 2)

        // Frequency label at axis
        let freqLabel = Text(String(format: "%.1f", radioFreqKHz))
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(nsColor: .systemRed))
        let resolvedLabel = context.resolve(freqLabel)
        let labelSize = resolvedLabel.measure(in: CGSize(width: 200, height: 20))

        let pillRect = CGRect(
            x: xPos - labelSize.width / 2 - 3,
            y: size.height - axisHeight + 1,
            width: labelSize.width + 6,
            height: axisHeight - 3
        )
        context.fill(Path(roundedRect: pillRect, cornerRadius: 3), with: .color(.black.opacity(0.7)))
        context.draw(resolvedLabel, at: CGPoint(x: xPos, y: size.height - axisHeight / 2), anchor: .center)
    }

    // MARK: - Frequency Axis

    func drawFrequencyAxis(context: GraphicsContext, size: CGSize, band: BandEdge) {
        let axisY = size.height - axisHeight

        var linePath = Path()
        linePath.move(to: CGPoint(x: 0, y: axisY))
        linePath.addLine(to: CGPoint(x: size.width, y: axisY))
        context.stroke(linePath, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

        let stepKHz = axisStep(for: band)
        var freq = (band.lowerKHz / stepKHz).rounded(.up) * stepKHz

        while freq <= band.upperKHz {
            let xPos = zoomedXPosition(frequencyKHz: freq, band: band, width: size.width)
            guard xPos >= -20, xPos <= size.width + 20 else {
                freq += stepKHz
                continue
            }

            var tickPath = Path()
            tickPath.move(to: CGPoint(x: xPos, y: axisY))
            tickPath.addLine(to: CGPoint(x: xPos, y: axisY + 4))
            context.stroke(tickPath, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)

            let label = Text(String(format: "%.0f", freq))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            context.draw(context.resolve(label), at: CGPoint(x: xPos, y: axisY + 13), anchor: .center)

            freq += stepKHz
        }
    }

    func axisStep(for band: BandEdge) -> Double {
        let visibleWidth = band.widthKHz / zoomScale
        if visibleWidth > 1_000 {
            return 200
        }
        if visibleWidth > 200 {
            return 50
        }
        if visibleWidth > 50 {
            return 10
        }
        return 5
    }
}
