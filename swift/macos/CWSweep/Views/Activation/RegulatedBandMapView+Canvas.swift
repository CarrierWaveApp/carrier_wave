import CarrierWaveCore
import SwiftUI

// MARK: - RegulatedBandMapView + Canvas Drawing

extension RegulatedBandMapView {
    // MARK: - Overview Strip

    func drawOverviewStrip(
        context: GraphicsContext, size: CGSize, band: BandEdge,
        segments: [BandSegment], license: LicenseClass
    ) {
        drawOverviewSegments(context: context, size: size, band: band, segments: segments)
        drawOverviewExtraHatch(
            context: context, size: size, band: band,
            segments: segments, license: license
        )
        drawOverviewBoundaryLine(context: context, size: size, band: band, segments: segments)
        drawOverviewLabels(context: context, size: size, band: band, segments: segments)
        drawOverviewVFOCursor(context: context, size: size, band: band)
    }

    // MARK: - Zoomed View

    func drawZoomedView(
        context: GraphicsContext, size: CGSize, band: BandEdge,
        spots: [EnrichedSpot], license: LicenseClass
    ) -> [(CGRect, EnrichedSpot)] {
        let drawH = size.height - axisHeight
        let center = effectiveZoomCenter
        let halfW = zoomHalfWidth

        drawZoomedBackground(context: context, size: size, band: band, license: license)
        let rects = drawZoomedSpots(
            context: context, size: size, drawableHeight: drawH,
            spots: spots, center: center, halfWidth: halfW
        )
        drawZoomedVFOCursor(context: context, size: size, drawableHeight: drawH, center: center, halfWidth: halfW)
        drawClearZoneIndicator(
            context: context, size: size, drawableHeight: drawH,
            spots: spots, center: center, halfWidth: halfW
        )
        drawZoomedAxis(context: context, size: size, center: center, halfWidth: halfW)
        return rects
    }
}

// MARK: - Overview Drawing Helpers

extension RegulatedBandMapView {
    func drawOverviewSegments(
        context: GraphicsContext, size: CGSize, band: BandEdge,
        segments: [BandSegment]
    ) {
        // Deduplicate by frequency range to avoid overdraw
        var drawn: Set<String> = []
        for seg in segments {
            let key = "\(seg.startMHz)-\(seg.endMHz)"
            guard !drawn.contains(key) else {
                continue
            }
            drawn.insert(key)

            let xStart = BandEdges.xPosition(frequencyKHz: seg.startMHz * 1_000, in: band)
            let xEnd = BandEdges.xPosition(frequencyKHz: seg.endMHz * 1_000, in: band)
            let rect = CGRect(
                x: xStart * size.width, y: 0,
                width: (xEnd - xStart) * size.width, height: size.height
            )
            let isCWDigital = seg.modes.contains("CW") || seg.modes.contains("DATA")
            let isPhone = seg.modes.contains("SSB") || seg.modes.contains("PHONE")
            let color: Color = isCWDigital && !isPhone
                ? .purple.opacity(0.2) : .green.opacity(0.15)
            context.fill(Path(rect), with: .color(color))
        }
    }

    func drawOverviewExtraHatch(
        context: GraphicsContext, size: CGSize, band: BandEdge,
        segments: [BandSegment], license: LicenseClass
    ) {
        guard license != .extra else {
            return
        }
        let extraSegs = extraOnlySegments(segments: segments, band: band)
        for seg in extraSegs {
            let xStart = BandEdges.xPosition(frequencyKHz: seg.startMHz * 1_000, in: band)
            let xEnd = BandEdges.xPosition(frequencyKHz: seg.endMHz * 1_000, in: band)
            let rect = CGRect(
                x: xStart * size.width, y: 0,
                width: (xEnd - xStart) * size.width, height: size.height
            )
            drawHatchPattern(context: context, rect: rect)
        }
    }

    func drawOverviewBoundaryLine(
        context: GraphicsContext, size: CGSize, band: BandEdge,
        segments: [BandSegment]
    ) {
        // Find boundaries between Extra-only and General segments
        let boundaries = extraBoundaryFrequencies(segments: segments, band: band)
        for freqMHz in boundaries {
            let xFrac = BandEdges.xPosition(frequencyKHz: freqMHz * 1_000, in: band)
            let xPos = xFrac * size.width
            var path = Path()
            path.move(to: CGPoint(x: xPos, y: 0))
            path.addLine(to: CGPoint(x: xPos, y: size.height))
            context.stroke(
                path, with: .color(.red),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
        }
    }

    func drawOverviewLabels(
        context: GraphicsContext, size: CGSize, band: BandEdge,
        segments: [BandSegment]
    ) {
        var drawn: Set<String> = []
        for seg in segments {
            let key = "\(seg.startMHz)-\(seg.endMHz)"
            guard !drawn.contains(key) else {
                continue
            }
            drawn.insert(key)

            let xStart = BandEdges.xPosition(frequencyKHz: seg.startMHz * 1_000, in: band)
            let xEnd = BandEdges.xPosition(frequencyKHz: seg.endMHz * 1_000, in: band)
            let segWidth = (xEnd - xStart) * size.width
            guard segWidth > 40 else {
                continue
            }

            let label = overviewLabel(for: seg)
            let text = Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
            let centerX = (xStart + xEnd) / 2 * size.width
            context.draw(
                context.resolve(text),
                at: CGPoint(x: centerX, y: size.height / 2),
                anchor: .center
            )
        }
    }

    func drawOverviewVFOCursor(context: GraphicsContext, size: CGSize, band: BandEdge) {
        let radioKHz = radioManager.frequency * 1_000
        guard radioKHz >= band.lowerKHz, radioKHz <= band.upperKHz else {
            return
        }
        let xFrac = BandEdges.xPosition(frequencyKHz: radioKHz, in: band)
        let xPos = xFrac * size.width
        var path = Path()
        path.move(to: CGPoint(x: xPos, y: 0))
        path.addLine(to: CGPoint(x: xPos, y: size.height))
        context.stroke(path, with: .color(.red.opacity(0.8)), lineWidth: 1.5)
    }
}

// MARK: - Zoomed Drawing Helpers

extension RegulatedBandMapView {
    func drawZoomedBackground(
        context: GraphicsContext, size: CGSize, band: BandEdge,
        license: LicenseClass
    ) {
        let center = effectiveZoomCenter
        let halfW = zoomHalfWidth
        let drawH = size.height - axisHeight

        // Draw extra-only hatching in zoom view
        guard license != .extra else {
            return
        }
        let extraSegs = extraOnlySegments(
            segments: bandSegmentsOnBand, band: band
        )
        for seg in extraSegs {
            let segStartKHz = seg.startMHz * 1_000
            let segEndKHz = seg.endMHz * 1_000
            let zoomLower = center - halfW
            let zoomUpper = center + halfW
            guard segEndKHz >= zoomLower, segStartKHz <= zoomUpper else {
                continue
            }

            let clampedStart = max(segStartKHz, zoomLower)
            let clampedEnd = min(segEndKHz, zoomUpper)
            let xStart = (clampedStart - zoomLower) / (halfW * 2)
            let xEnd = (clampedEnd - zoomLower) / (halfW * 2)
            let rect = CGRect(
                x: xStart * size.width, y: 0,
                width: (xEnd - xStart) * size.width, height: drawH
            )
            drawHatchPattern(context: context, rect: rect)
        }
    }

    // swiftlint:disable:next function_parameter_count
    func drawZoomedSpots(
        context: GraphicsContext, size: CGSize, drawableHeight: CGFloat,
        spots: [EnrichedSpot], center: Double, halfWidth: Double
    ) -> [(CGRect, EnrichedSpot)] {
        let zoomLower = center - halfWidth
        let zoomWidth = halfWidth * 2
        let visible = spots.filter {
            $0.spot.frequencyKHz >= zoomLower
                && $0.spot.frequencyKHz <= center + halfWidth
        }

        var lanes: [[EnrichedSpot]] = []
        var rects: [(CGRect, EnrichedSpot)] = []

        for spot in visible {
            let xPos = ((spot.spot.frequencyKHz - zoomLower) / zoomWidth) * size.width
            var placed = false
            for idx in lanes.indices {
                let overlaps = lanes[idx].contains { existing in
                    let existX = ((existing.spot.frequencyKHz - zoomLower) / zoomWidth) * size.width
                    return abs(xPos - existX) < 70
                }
                if !overlaps {
                    lanes[idx].append(spot)
                    placed = true
                    break
                }
            }
            if !placed {
                lanes.append([spot])
            }
        }

        let markerH: CGFloat = 18
        for (laneIdx, lane) in lanes.enumerated() {
            let yBase = CGFloat(laneIdx) * (markerH + 2) + 4
            guard yBase + markerH < drawableHeight else {
                continue
            }
            drawZoomLane(
                lane, yBase: yBase, markerH: markerH,
                zoomLower: zoomLower, zoomWidth: zoomWidth,
                size: size, context: context, rects: &rects
            )
        }
        return rects
    }

    // swiftlint:disable:next function_parameter_count
    private func drawZoomLane(
        _ lane: [EnrichedSpot], yBase: CGFloat, markerH: CGFloat,
        zoomLower: Double, zoomWidth: Double,
        size: CGSize, context: GraphicsContext, rects: inout [(CGRect, EnrichedSpot)]
    ) {
        let context = context
        for spot in lane {
            let xFrac = (spot.spot.frequencyKHz - zoomLower) / zoomWidth
            let xPos = xFrac * size.width
            let color = spotColor(for: spot)
            let prefix = spotPrefix(for: spot)
            let label = "\(prefix)\(spot.spot.callsign)"

            let labelW: CGFloat = max(60, CGFloat(label.count) * 7)
            let rect = CGRect(x: xPos - labelW / 2, y: yBase, width: labelW, height: markerH)

            let ageSeconds = Date().timeIntervalSince(spot.spot.timestamp)
            let opacity = max(0.3, 1.0 - (ageSeconds / 1_800) * 0.7)

            let chip = Path(roundedRect: rect, cornerRadius: 4)
            context.fill(chip, with: .color(color.opacity(opacity * 0.25)))
            context.stroke(chip, with: .color(color.opacity(opacity)), lineWidth: 0.5)

            let text = Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(color.opacity(opacity))
            context.draw(
                context.resolve(text),
                at: CGPoint(x: xPos, y: yBase + markerH / 2),
                anchor: .center
            )
            rects.append((rect, spot))
        }
    }

    func drawZoomedVFOCursor(
        context: GraphicsContext, size: CGSize, drawableHeight: CGFloat,
        center: Double, halfWidth: Double
    ) {
        let radioKHz = radioManager.frequency * 1_000
        let zoomLower = center - halfWidth
        let zoomWidth = halfWidth * 2
        let xFrac = (radioKHz - zoomLower) / zoomWidth
        guard xFrac >= 0, xFrac <= 1 else {
            return
        }

        let xPos = xFrac * size.width
        var path = Path()
        path.move(to: CGPoint(x: xPos, y: 0))
        path.addLine(to: CGPoint(x: xPos, y: drawableHeight))
        context.stroke(path, with: .color(.red.opacity(0.8)), lineWidth: 1.5)

        // Triangle marker at top
        let tri = Text("\u{25BC}")
            .font(.system(size: 8))
            .foregroundStyle(.red)
        context.draw(context.resolve(tri), at: CGPoint(x: xPos, y: 2), anchor: .top)
    }

    // swiftlint:disable:next function_parameter_count
    func drawClearZoneIndicator(
        context: GraphicsContext, size: CGSize, drawableHeight: CGFloat,
        spots: [EnrichedSpot], center: Double, halfWidth: Double
    ) {
        let radioKHz = radioManager.frequency * 1_000
        let clearHz = 600.0
        let clearKHz = clearHz / 1_000.0
        let nearby = spots.contains { abs($0.spot.frequencyKHz - radioKHz) <= clearKHz }
        guard !nearby else {
            return
        }

        let zoomLower = center - halfWidth
        let zoomWidth = halfWidth * 2
        let xFrac = (radioKHz - zoomLower) / zoomWidth
        guard xFrac >= 0, xFrac <= 1 else {
            return
        }

        // Dashed green border around clear zone
        let leftFrac = max(0, (radioKHz - clearKHz - zoomLower) / zoomWidth)
        let rightFrac = min(1, (radioKHz + clearKHz - zoomLower) / zoomWidth)
        let rect = CGRect(
            x: leftFrac * size.width, y: 2,
            width: (rightFrac - leftFrac) * size.width, height: drawableHeight - 4
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 3),
            with: .color(.green.opacity(0.6)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
        )

        let label = Text("clear \u{00B1}600 Hz")
            .font(.system(size: 7, weight: .medium))
            .foregroundStyle(.green.opacity(0.8))
        context.draw(
            context.resolve(label),
            at: CGPoint(x: xFrac * size.width, y: drawableHeight - 8),
            anchor: .center
        )
    }

    func drawZoomedAxis(
        context: GraphicsContext, size: CGSize,
        center: Double, halfWidth: Double
    ) {
        let axisY = size.height - axisHeight
        var line = Path()
        line.move(to: CGPoint(x: 0, y: axisY))
        line.addLine(to: CGPoint(x: size.width, y: axisY))
        context.stroke(line, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)

        let zoomLower = center - halfWidth
        let zoomWidth = halfWidth * 2
        let step = zoomAxisStep(zoomWidth: zoomWidth)
        var freq = (zoomLower / step).rounded(.up) * step

        while freq <= center + halfWidth {
            let xFrac = (freq - zoomLower) / zoomWidth
            let xPos = xFrac * size.width
            var tick = Path()
            tick.move(to: CGPoint(x: xPos, y: axisY))
            tick.addLine(to: CGPoint(x: xPos, y: axisY + 4))
            context.stroke(tick, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)

            let label = Text(String(format: "%.1f", freq))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            context.draw(
                context.resolve(label),
                at: CGPoint(x: xPos, y: axisY + 12),
                anchor: .center
            )
            freq += step
        }
    }
}

// MARK: - Shared Helpers

extension RegulatedBandMapView {
    func spotColor(for spot: EnrichedSpot) -> Color {
        switch spot.spot.source {
        case .pota:
            Color(red: 0.290, green: 0.851, blue: 0.502) // #4ade80
        case .sota,
             .wwff:
            Color(red: 0.220, green: 0.745, blue: 0.973) // #38bdf8
        default:
            Color(red: 0.961, green: 0.620, blue: 0.043) // #f59e0b
        }
    }

    func spotPrefix(for spot: EnrichedSpot) -> String {
        spot.spot.source == .pota ? "\u{1F332}" : ""
    }

    func overviewLabel(for seg: BandSegment) -> String {
        let isCW = seg.modes.contains("CW") || seg.modes.contains("DATA")
        let isPhone = seg.modes.contains("SSB") || seg.modes.contains("PHONE")
        if seg.minimumLicense == .extra {
            return "EXTRA ONLY"
        }
        if isCW, !isPhone {
            return "CW/Digital"
        }
        if isPhone, !isCW {
            return "Phone"
        }
        return "All Modes"
    }

    func extraOnlySegments(segments: [BandSegment], band: BandEdge) -> [BandSegment] {
        // A frequency range is Extra-only if covered by Extra segments but NOT General/Tech
        segments.filter { seg in
            guard seg.minimumLicense == .extra, seg.band == band.id else {
                return false
            }
            // Check if any non-Extra segment overlaps this range
            let nonExtra = segments.filter { other in
                other.minimumLicense != .extra && other.band == band.id
                    && other.endMHz > seg.startMHz && other.startMHz < seg.endMHz
            }
            return nonExtra.isEmpty
        }
    }

    func extraBoundaryFrequencies(
        segments: [BandSegment], band: BandEdge
    ) -> [Double] {
        let extraSegs = extraOnlySegments(segments: segments, band: band)
        var boundaries: Set<Double> = []
        for seg in extraSegs {
            boundaries.insert(seg.endMHz)
        }
        return boundaries.sorted()
    }

    func drawHatchPattern(context: GraphicsContext, rect: CGRect) {
        var hatch = Path()
        let spacing: CGFloat = 6
        var offset: CGFloat = 0
        while offset < rect.width + rect.height {
            hatch.move(to: CGPoint(
                x: rect.minX + offset, y: rect.minY
            ))
            hatch.addLine(to: CGPoint(
                x: rect.minX + offset - rect.height, y: rect.maxY
            ))
            offset += spacing
        }
        var clipped = context
        clipped.clip(to: Path(rect))
        clipped.stroke(
            hatch, with: .color(.red.opacity(0.15)),
            lineWidth: 1
        )
    }

    func zoomAxisStep(zoomWidth: Double) -> Double {
        if zoomWidth > 50 {
            return 10
        }
        if zoomWidth > 20 {
            return 5
        }
        if zoomWidth > 10 {
            return 2
        }
        return 1
    }
}
