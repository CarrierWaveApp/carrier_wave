import CarrierWaveCore
import SwiftUI

// MARK: - Layout Constants

extension ContestBandScopeView {
    static let axisColumnWidth: CGFloat = 56
    static let gutterWidth: CGFloat = 50
    static let rowHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 1
    static var rowsLeftEdge: CGFloat {
        axisColumnWidth + gutterWidth
    }
}

// MARK: - SpotRowLayout

struct SpotRowLayout {
    let spot: EnrichedSpot
    let axisY: CGFloat
    var rowY: CGFloat

    var isDisplaced: Bool {
        abs(rowY - axisY) > 1
    }
}

// MARK: - Canvas Rendering

extension ContestBandScopeView {
    func scopeCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            guard let band = selectedBand else {
                return
            }
            var rects: [(CGRect, EnrichedSpot)] = []
            drawSubBandShading(ctx: context, size: canvasSize, band: band)
            drawWaterfall(ctx: context, size: canvasSize, band: band)
            drawBookmarks(ctx: context, size: canvasSize, band: band)
            drawVFOCursor(ctx: context, size: canvasSize, band: band)
            let layouts = computeRowLayouts(size: canvasSize, band: band)
            drawFrequencyAxis(ctx: context, size: canvasSize, band: band, layouts: layouts)
            drawLeaderLines(ctx: context, size: canvasSize, layouts: layouts)
            var mutableCtx = context
            drawSpotRows(ctx: &mutableCtx, size: canvasSize, band: band, layouts: layouts, rects: &rects)
            Task { @MainActor in hitRects.rects = rects }
        }
        .accessibilityLabel("Vertical band scope: \(spotsOnBand.count) spots on \(selectedBandId)")
    }

    func yPosForFreq(_ freqKHz: Double, band: BandEdge, height: CGFloat) -> CGFloat {
        let frac = (freqKHz - band.lowerKHz) / band.widthKHz
        let visibleHeight = 1.0 / zoomScale
        let visibleStart = panOffset - visibleHeight / 2
        let normalizedY = (frac - visibleStart) / visibleHeight
        return normalizedY * height
    }

    /// Inverse of yPosForFreq: convert a y position to a frequency (zoom/pan aware)
    func freqForYPos(_ yPos: CGFloat, band: BandEdge, height: CGFloat) -> Double {
        let normalizedY = yPos / height
        let visibleHeight = 1.0 / zoomScale
        let visibleStart = panOffset - visibleHeight / 2
        let frac = normalizedY * visibleHeight + visibleStart
        return band.lowerKHz + frac * band.widthKHz
    }

    func clampPan(_ value: CGFloat) -> CGFloat {
        let halfVisible = 0.5 / zoomScale
        return min(max(value, halfVisible), 1.0 - halfVisible)
    }

    /// Drag to pan when zoomed
    func panGesture(canvasHeight: CGFloat) -> some Gesture {
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
            }
    }

    /// Pinch to zoom
    func zoomGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoomScale = max(1.0, min(16.0, zoomBaseScale * value.magnification))
            }
            .onEnded { _ in
                zoomBaseScale = zoomScale
                panOffset = clampPan(panOffset)
                panBaseOffset = panOffset
                saveBandZoomState()
            }
    }

    func drawSubBandShading(ctx: GraphicsContext, size: CGSize, band: BandEdge) {
        let axisX = Self.axisColumnWidth

        if let digitalBound = band.digitalBoundaryKHz {
            let yTop = yPosForFreq(band.lowerKHz, band: band, height: size.height)
            let yBottom = yPosForFreq(digitalBound, band: band, height: size.height)
            let rect = CGRect(x: axisX, y: yTop, width: size.width - axisX, height: yBottom - yTop)
            ctx.fill(Path(rect), with: .color(.blue.opacity(0.12)))

            let label = Text("CW / DIGITAL")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemBlue).opacity(0.8))
            ctx.draw(ctx.resolve(label), at: CGPoint(x: axisX + 6, y: yTop + 14), anchor: .leading)
        }

        if let ssbBound = band.ssbBoundaryKHz {
            let yTop = yPosForFreq(ssbBound, band: band, height: size.height)
            let yBottom = yPosForFreq(band.upperKHz, band: band, height: size.height)
            let rect = CGRect(x: axisX, y: yTop, width: size.width - axisX, height: yBottom - yTop)
            ctx.fill(Path(rect), with: .color(.orange.opacity(0.10)))

            let label = Text("SSB / PHONE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemOrange).opacity(0.8))
            ctx.draw(ctx.resolve(label), at: CGPoint(x: axisX + 6, y: yTop + 14), anchor: .leading)

            var boundary = Path()
            boundary.move(to: CGPoint(x: axisX, y: yTop))
            boundary.addLine(to: CGPoint(x: size.width, y: yTop))
            ctx.stroke(
                boundary,
                with: .color(.white.opacity(0.16)),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
            )
        }
    }

    func drawBookmarks(ctx: GraphicsContext, size: CGSize, band: BandEdge) {
        for bookmark in bookmarksOnBand {
            let yPosition = yPosForFreq(bookmark.frequencyKHz, band: band, height: size.height)
            let axisX = Self.axisColumnWidth

            var flag = Path()
            flag.move(to: CGPoint(x: axisX, y: yPosition))
            flag.addLine(to: CGPoint(x: axisX - 8, y: yPosition - 5))
            flag.addLine(to: CGPoint(x: axisX - 8, y: yPosition + 5))
            flag.closeSubpath()
            ctx.fill(flag, with: .color(Color(nsColor: .systemOrange)))

            var line = Path()
            line.move(to: CGPoint(x: axisX, y: yPosition))
            line.addLine(to: CGPoint(x: size.width, y: yPosition))
            ctx.stroke(
                line,
                with: .color(Color(nsColor: .systemOrange).opacity(0.4)),
                style: StrokeStyle(lineWidth: 0.5, dash: [1, 4])
            )

            let label = Text(bookmark.frequencyDisplay)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(nsColor: .systemOrange))
            ctx.draw(ctx.resolve(label), at: CGPoint(x: axisX - 10, y: yPosition), anchor: .trailing)
        }
    }

    func drawVFOCursor(ctx: GraphicsContext, size: CGSize, band: BandEdge) {
        let radioFreqKHz = radioManager.frequency * 1_000
        guard radioFreqKHz >= band.lowerKHz, radioFreqKHz <= band.upperKHz else {
            return
        }

        let yPosition = yPosForFreq(radioFreqKHz, band: band, height: size.height)
        let axisX = Self.axisColumnWidth

        let family = ModeEquivalence.family(for: radioManager.mode)
        let halfKHz = switch family {
        case .cw: 0.25
        case .digital: 1.5
        case .phone: 1.2
        case .other: 1.5
        }
        let filterWidthHz = Int(halfKHz * 2_000)
        let yTop = yPosForFreq(radioFreqKHz - halfKHz, band: band, height: size.height)
        let yBot = yPosForFreq(radioFreqKHz + halfKHz, band: band, height: size.height)
        let filterRect = CGRect(x: axisX, y: yTop, width: size.width - axisX, height: yBot - yTop)
        ctx.fill(Path(filterRect), with: .color(Color(nsColor: .systemBlue).opacity(0.12)))

        var line = Path()
        line.move(to: CGPoint(x: 0, y: yPosition))
        line.addLine(to: CGPoint(x: size.width, y: yPosition))
        ctx.stroke(line, with: .color(Color(nsColor: .systemRed).opacity(0.85)), lineWidth: 1.5)

        let modeLabel = family == .cw ? "CW" : family == .phone ? "SSB" : "DIG"
        let label = Text("\(modeLabel) · \(filterWidthHz) Hz")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(nsColor: .systemRed))
        ctx.draw(ctx.resolve(label), at: CGPoint(x: axisX - 2, y: yPosition - 4), anchor: .trailing)
    }

    // MARK: - Three-Column Layout Helpers

    /// Compute row layouts with displacement to avoid overlaps.
    func computeRowLayouts(size: CGSize, band: BandEdge) -> [SpotRowLayout] {
        let spots = sortedSpots.filter { spot in
            let yp = yPosForFreq(spot.spot.frequencyKHz, band: band, height: size.height)
            return yp > -Self.rowHeight && yp < size.height + Self.rowHeight
        }

        var layouts: [SpotRowLayout] = spots.map { spot in
            let axisY = yPosForFreq(spot.spot.frequencyKHz, band: band, height: size.height)
            return SpotRowLayout(spot: spot, axisY: axisY, rowY: axisY)
        }

        guard layouts.count > 1 else {
            return layouts
        }
        let minGap = Self.rowHeight + Self.rowSpacing
        for idx in 1 ..< layouts.count {
            let prevBottom = layouts[idx - 1].rowY + Self.rowHeight / 2
            let desired = layouts[idx].rowY
            if desired - prevBottom < minGap {
                layouts[idx].rowY = prevBottom + minGap - Self.rowHeight / 2
            }
        }

        return layouts
    }

    func drawFrequencyAxis(
        ctx: GraphicsContext,
        size: CGSize,
        band: BandEdge,
        layouts: [SpotRowLayout]
    ) {
        let axisX = Self.axisColumnWidth
        let stepKHz = axisStep(for: band)
        var freq = (band.lowerKHz / stepKHz).rounded(.up) * stepKHz

        // Draw regular interval ticks
        while freq <= band.upperKHz {
            let yPosition = yPosForFreq(freq, band: band, height: size.height)
            guard yPosition > -20, yPosition < size.height + 20 else {
                freq += stepKHz
                continue
            }

            var tick = Path()
            tick.move(to: CGPoint(x: axisX - 4, y: yPosition))
            tick.addLine(to: CGPoint(x: axisX, y: yPosition))
            ctx.stroke(tick, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)

            let label = Text(String(format: "%.0f", freq))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
            ctx.draw(ctx.resolve(label), at: CGPoint(x: axisX - 6, y: yPosition), anchor: .trailing)

            freq += stepKHz
        }

        // Draw spot ticks on axis
        for layout in layouts {
            let yPosition = layout.axisY
            guard yPosition > -20, yPosition < size.height + 20 else {
                continue
            }

            let spot = layout.spot
            let color = SpotColorScheme.markerColor(for: spot, mode: colorMode, isWorkedToday: false)
            let opacity = ageOpacity(for: spot)
            let isNeeded = spot.neededStatus == .newEntity || spot.neededStatus == .newBandSlot

            var tick = Path()
            tick.move(to: CGPoint(x: axisX - 6, y: yPosition))
            tick.addLine(to: CGPoint(x: axisX, y: yPosition))
            ctx.stroke(
                tick,
                with: .color(color.opacity(opacity)),
                lineWidth: isNeeded ? 2 : 1
            )
        }
    }

    func drawLeaderLines(ctx: GraphicsContext, size: CGSize, layouts: [SpotRowLayout]) {
        let axisX = Self.axisColumnWidth
        let rowsX = Self.rowsLeftEdge

        for layout in layouts {
            let spot = layout.spot
            let color = SpotColorScheme.markerColor(for: spot, mode: colorMode, isWorkedToday: false)
            let opacity = ageOpacity(for: spot)
            let isNeeded = spot.neededStatus == .newEntity || spot.neededStatus == .newBandSlot

            var line = Path()
            line.move(to: CGPoint(x: axisX, y: layout.axisY))
            line.addLine(to: CGPoint(x: rowsX, y: layout.rowY))
            ctx.stroke(
                line,
                with: .color(color.opacity(opacity * 0.7)),
                lineWidth: isNeeded ? 1.5 : 0.75
            )
        }
    }

    func drawSpotRows(
        ctx: inout GraphicsContext,
        size: CGSize,
        band: BandEdge,
        layouts: [SpotRowLayout],
        rects: inout [(CGRect, EnrichedSpot)]
    ) {
        let rowsX = Self.rowsLeftEdge
        let rowsWidth = size.width - rowsX
        let selectedId = selectionState.selectedSpot?.id

        for layout in layouts {
            let rowY = layout.rowY
            guard rowY > -Self.rowHeight, rowY < size.height + Self.rowHeight else {
                continue
            }
            let hitRect = drawSpotRow(
                ctx: &ctx,
                layout: layout,
                rowsX: rowsX,
                rowsWidth: rowsWidth,
                isSelected: layout.spot.id == selectedId
            )
            rects.append((hitRect, layout.spot))
        }
    }

    private func drawSpotRow(
        ctx: inout GraphicsContext,
        layout: SpotRowLayout,
        rowsX: CGFloat,
        rowsWidth: CGFloat,
        isSelected: Bool
    ) -> CGRect {
        let spot = layout.spot
        let rowY = layout.rowY
        let color = SpotColorScheme.markerColor(for: spot, mode: colorMode, isWorkedToday: false)
        let opacity = ageOpacity(for: spot)
        let isNeeded = spot.neededStatus == .newEntity || spot.neededStatus == .newBandSlot
        let rowRect = CGRect(x: rowsX, y: rowY - Self.rowHeight / 2, width: rowsWidth, height: Self.rowHeight)

        if isSelected {
            ctx.fill(
                Path(roundedRect: rowRect, cornerRadius: 3),
                with: .color(Color(nsColor: .systemYellow).opacity(0.18))
            )
            ctx.stroke(
                Path(roundedRect: rowRect, cornerRadius: 3),
                with: .color(Color(nsColor: .systemYellow)),
                lineWidth: 1.5
            )
        }

        let callX = drawPriorityBadge(ctx: &ctx, spot: spot, rowsX: rowsX, rowY: rowY, opacity: opacity)

        let weight: Font.Weight = isNeeded ? .bold : .medium
        let fontSize: CGFloat = isNeeded ? 10 : 9
        let callLabel = Text(spot.spot.callsign)
            .font(.system(size: fontSize, weight: weight, design: .monospaced))
            .foregroundStyle(color.opacity(opacity))
        ctx.draw(ctx.resolve(callLabel), at: CGPoint(x: callX, y: rowY), anchor: .leading)

        drawRowMeta(
            ctx: &ctx, spot: spot, opacity: opacity,
            rightEdgeX: rowsX + rowsWidth - 4, rowY: rowY
        )

        var dot = Path()
        dot.addEllipse(in: CGRect(x: rowsX - 2, y: rowY - 2, width: 4, height: 4))
        ctx.fill(dot, with: .color(color.opacity(opacity * 0.6)))

        return rowRect
    }

    private func drawPriorityBadge(
        ctx: inout GraphicsContext,
        spot: EnrichedSpot,
        rowsX: CGFloat,
        rowY: CGFloat,
        opacity: Double
    ) -> CGFloat {
        let baseX = rowsX + 4
        if spot.neededStatus == .newEntity {
            let badgeWidth = drawBadge(
                ctx: &ctx, text: "NEW ENT", at: CGPoint(x: baseX, y: rowY),
                color: Color(nsColor: .systemPurple), opacity: opacity
            )
            return baseX + badgeWidth + 6
        } else if spot.neededStatus == .newBandSlot {
            let badgeWidth = drawBadge(
                ctx: &ctx, text: "NEW BAND", at: CGPoint(x: baseX, y: rowY),
                color: Color(nsColor: .systemGreen), opacity: opacity
            )
            return baseX + badgeWidth + 6
        }
        return baseX
    }

    private func drawRowMeta(
        ctx: inout GraphicsContext,
        spot: EnrichedSpot,
        opacity: Double,
        rightEdgeX: CGFloat,
        rowY: CGFloat
    ) {
        let ageSeconds = Int(Date().timeIntervalSince(spot.spot.timestamp))
        let ageStr = ageSeconds < 60 ? "\(ageSeconds)s" : "\(ageSeconds / 60)m"
        let metaLabel = Text("\(spot.spot.source.shortName) \(ageStr)")
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(.secondary.opacity(opacity))
        ctx.draw(
            ctx.resolve(metaLabel),
            at: CGPoint(x: rightEdgeX, y: rowY),
            anchor: .trailing
        )
    }

    // MARK: - Badge Helper

    @discardableResult
    private func drawBadge(
        ctx: inout GraphicsContext,
        text: String,
        at point: CGPoint,
        color: Color,
        opacity: Double
    ) -> CGFloat {
        let label = Text(text)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(color.opacity(opacity))
        let resolved = ctx.resolve(label)
        let measured = resolved.measure(in: CGSize(width: 200, height: Self.rowHeight))
        let badgeRect = CGRect(
            x: point.x, y: point.y - measured.height / 2 - 1,
            width: measured.width + 4, height: measured.height + 2
        )
        ctx.fill(
            Path(roundedRect: badgeRect, cornerRadius: 2),
            with: .color(color.opacity(opacity * 0.2))
        )
        ctx.stroke(
            Path(roundedRect: badgeRect, cornerRadius: 2),
            with: .color(color.opacity(opacity * 0.6)),
            lineWidth: 0.5
        )
        ctx.draw(resolved, at: CGPoint(x: point.x + 2, y: point.y), anchor: .leading)
        return measured.width + 4
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
        if visibleWidth > 20 {
            return 5
        }
        return 2
    }
}
