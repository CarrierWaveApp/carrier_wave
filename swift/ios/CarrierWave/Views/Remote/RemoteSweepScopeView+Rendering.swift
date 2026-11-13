import CarrierWaveCore
import SwiftUI

// MARK: - Rendering + geometry helpers

//
// Extracted from `RemoteSweepScopeView` so the main file fits SwiftLint's
// `type_body_length` cap. Mirrors the macOS `ContestBandScopeView+Rendering`
// pattern.

extension RemoteSweepScopeView {
    // MARK: - Geometry (zoom + pan aware)

    func yPosition(
        forFreqHz freqHz: Double,
        range: (lowMHz: Double, highMHz: Double),
        height: CGFloat
    ) -> CGFloat {
        let lowHz = range.lowMHz * 1_000_000
        let highHz = range.highMHz * 1_000_000
        let span = highHz - lowHz
        guard span > 0 else {
            return 0
        }
        let frac = (freqHz - lowHz) / span
        let visibleHeight = 1.0 / zoomScale
        let visibleStart = Double(panOffset) - visibleHeight / 2
        let normalized = (frac - visibleStart) / visibleHeight
        return CGFloat(normalized) * height
    }

    func freqHz(
        atY y: CGFloat,
        in height: CGFloat,
        range: (lowMHz: Double, highMHz: Double)
    ) -> UInt64 {
        let normalized = max(0, min(1, Double(y / max(height, 1))))
        let visibleHeight = 1.0 / zoomScale
        let visibleStart = Double(panOffset) - visibleHeight / 2
        let frac = normalized * visibleHeight + visibleStart
        let lowHz = range.lowMHz * 1_000_000
        let highHz = range.highMHz * 1_000_000
        return UInt64((lowHz + frac * (highHz - lowHz)).rounded())
    }

    // MARK: - Sub-band shading

    func drawSubBandShading(
        context: GraphicsContext,
        size: CGSize,
        band: String,
        range: (lowMHz: Double, highMHz: Double)
    ) {
        let axisX = Self.axisColumnWidth
        let lowHz = range.lowMHz * 1_000_000
        let highHz = range.highMHz * 1_000_000

        if let digitalBoundKHz = BandUtilities.digitalBoundaryKHz(forBand: band) {
            let yTop = yPosition(forFreqHz: lowHz, range: range, height: size.height)
            let yBottom = yPosition(forFreqHz: digitalBoundKHz * 1_000, range: range, height: size.height)
            let rect = CGRect(x: axisX, y: yTop, width: size.width - axisX, height: yBottom - yTop)
            context.fill(Path(rect), with: .color(.blue.opacity(0.18)))
            let label = Text("CW / DIGITAL")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.blue.opacity(0.85))
            context.draw(context.resolve(label), at: CGPoint(x: axisX + 6, y: yTop + 12), anchor: .leading)
        }

        if let ssbBoundKHz = BandUtilities.ssbBoundaryKHz(forBand: band) {
            let yTop = yPosition(forFreqHz: ssbBoundKHz * 1_000, range: range, height: size.height)
            let yBottom = yPosition(forFreqHz: highHz, range: range, height: size.height)
            let rect = CGRect(x: axisX, y: yTop, width: size.width - axisX, height: yBottom - yTop)
            context.fill(Path(rect), with: .color(.orange.opacity(0.14)))
            let label = Text("SSB / PHONE")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.85))
            context.draw(context.resolve(label), at: CGPoint(x: axisX + 6, y: yTop + 12), anchor: .leading)

            var boundary = Path()
            boundary.move(to: CGPoint(x: axisX, y: yTop))
            boundary.addLine(to: CGPoint(x: size.width, y: yTop))
            context.stroke(
                boundary,
                with: .color(.white.opacity(0.16)),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
            )
        }
    }

    // MARK: - Frequency axis

    func drawFrequencyAxis(
        context: GraphicsContext,
        size: CGSize,
        range: (lowMHz: Double, highMHz: Double),
        layouts: [SpotRowLayout]
    ) {
        let axisX = Self.axisColumnWidth
        let widthKHz = (range.highMHz - range.lowMHz) * 1_000
        let stepKHz = axisStep(forVisibleKHz: widthKHz / Double(zoomScale))
        var freq = (range.lowMHz * 1_000 / stepKHz).rounded(.up) * stepKHz
        let highKHz = range.highMHz * 1_000

        while freq <= highKHz {
            let y = yPosition(forFreqHz: freq * 1_000, range: range, height: size.height)
            if y > -20, y < size.height + 20 {
                var tick = Path()
                tick.move(to: CGPoint(x: axisX - 4, y: y))
                tick.addLine(to: CGPoint(x: axisX, y: y))
                context.stroke(tick, with: .color(.gray.opacity(0.5)), lineWidth: 0.5)

                let label = Text(formatAxisLabel(khz: freq))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.gray.opacity(0.85))
                context.draw(
                    context.resolve(label),
                    at: CGPoint(x: axisX - 6, y: y),
                    anchor: .trailing
                )
            }
            freq += stepKHz
        }

        for layout in layouts {
            guard layout.axisY > -10, layout.axisY < size.height + 10 else {
                continue
            }
            let color = markerColor(for: layout.spot)
            let opacity = ageOpacity(for: layout.spot)
            var tick = Path()
            tick.move(to: CGPoint(x: axisX - 6, y: layout.axisY))
            tick.addLine(to: CGPoint(x: axisX, y: layout.axisY))
            context.stroke(
                tick,
                with: .color(color.opacity(opacity)),
                lineWidth: layout.spot.needed ? 2 : 1
            )
        }
    }

    // MARK: - Leader lines

    func drawLeaderLines(context: GraphicsContext, layouts: [SpotRowLayout]) {
        let axisX = Self.axisColumnWidth
        let rowsX = Self.rowsLeftEdge
        for layout in layouts {
            let color = markerColor(for: layout.spot)
            let opacity = ageOpacity(for: layout.spot)
            var line = Path()
            line.move(to: CGPoint(x: axisX, y: layout.axisY))
            line.addLine(to: CGPoint(x: rowsX, y: layout.rowY))
            context.stroke(
                line,
                with: .color(color.opacity(opacity * 0.7)),
                lineWidth: layout.spot.needed ? 1.5 : 0.75
            )
        }
    }

    // MARK: - VFO cursor

    func drawVFOCursor(
        context: GraphicsContext,
        size: CGSize,
        range: (lowMHz: Double, highMHz: Double),
        freqHz: UInt64,
        mode: String
    ) {
        let lowHz = range.lowMHz * 1_000_000
        let highHz = range.highMHz * 1_000_000
        guard Double(freqHz) >= lowHz, Double(freqHz) <= highHz else {
            return
        }

        let y = yPosition(forFreqHz: Double(freqHz), range: range, height: size.height)
        let axisX = Self.axisColumnWidth

        let halfKHz = filterHalfWidthKHz(forMode: mode)
        let yTop = yPosition(forFreqHz: Double(freqHz) - halfKHz * 1_000, range: range, height: size.height)
        let yBot = yPosition(forFreqHz: Double(freqHz) + halfKHz * 1_000, range: range, height: size.height)
        let filterRect = CGRect(x: axisX, y: yTop, width: size.width - axisX, height: yBot - yTop)
        context.fill(Path(filterRect), with: .color(.red.opacity(0.18)))

        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(line, with: .color(.red.opacity(0.85)), lineWidth: 1.5)

        let widthHz = Int(halfKHz * 2_000)
        let label = Text("\(modeShortName(mode)) · \(widthHz) Hz")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.red)
        context.draw(context.resolve(label), at: CGPoint(x: axisX - 2, y: y - 4), anchor: .trailing)
    }

    // MARK: - Spot rows

    func computeRowLayouts(
        spots: [RemoteSpot],
        range: (lowMHz: Double, highMHz: Double),
        height: CGFloat
    ) -> [SpotRowLayout] {
        let sorted = spots.sorted { $0.freqHz < $1.freqHz }
        let visible = sorted.compactMap { spot -> SpotRowLayout? in
            let y = yPosition(forFreqHz: Double(spot.freqHz), range: range, height: height)
            guard y > -Self.rowHeight, y < height + Self.rowHeight else {
                return nil
            }
            return SpotRowLayout(spot: spot, axisY: y, rowY: y)
        }

        guard visible.count > 1 else {
            return visible
        }
        var layouts = visible
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

    func drawSpotRows(
        context: GraphicsContext,
        size: CGSize,
        layouts: [SpotRowLayout],
        selectedID: String?,
        rects: inout [(CGRect, RemoteSpot)]
    ) {
        let rowsX = Self.rowsLeftEdge
        let rowsWidth = size.width - rowsX - 4

        for layout in layouts {
            guard layout.rowY > -Self.rowHeight, layout.rowY < size.height + Self.rowHeight else {
                continue
            }
            let rect = drawSpotRow(
                context: context,
                layout: layout,
                rowsX: rowsX,
                rowsWidth: rowsWidth,
                isSelected: layout.spot.id == selectedID
            )
            rects.append((rect, layout.spot))
        }
    }

    private func drawSpotRow(
        context: GraphicsContext,
        layout: SpotRowLayout,
        rowsX: CGFloat,
        rowsWidth: CGFloat,
        isSelected: Bool
    ) -> CGRect {
        let spot = layout.spot
        let rowY = layout.rowY
        let color = markerColor(for: spot)
        let opacity = ageOpacity(for: spot)
        let rect = CGRect(x: rowsX, y: rowY - Self.rowHeight / 2, width: rowsWidth, height: Self.rowHeight)

        if isSelected {
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(.yellow.opacity(0.18)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(.yellow), lineWidth: 1.5)
        }

        var dot = Path()
        dot.addEllipse(in: CGRect(x: rowsX - 4, y: rowY - 2.5, width: 5, height: 5))
        context.fill(dot, with: .color(color.opacity(opacity)))

        var x = rowsX + 6

        if spot.needed {
            let badgeWidth = drawBadge(
                context: context,
                text: "NEW",
                at: CGPoint(x: x, y: rowY),
                color: .purple,
                opacity: opacity
            )
            x += badgeWidth + 6
        }

        let weight: Font.Weight = spot.needed ? .bold : .medium
        let fontSize: CGFloat = spot.needed ? 11 : 10
        let callLabel = Text(spot.callsign)
            .font(.system(size: fontSize, weight: weight, design: .monospaced))
            .foregroundStyle(color.opacity(opacity))
        context.draw(context.resolve(callLabel), at: CGPoint(x: x, y: rowY), anchor: .leading)

        let ageStr = ageString(for: spot.spottedAt)
        let metaLabel = Text("\(spot.source.uppercased()) \(ageStr)")
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(Color.gray.opacity(opacity))
        context.draw(
            context.resolve(metaLabel),
            at: CGPoint(x: rowsX + rowsWidth - 4, y: rowY),
            anchor: .trailing
        )

        return rect
    }

    @discardableResult
    private func drawBadge(
        context: GraphicsContext,
        text: String,
        at point: CGPoint,
        color: Color,
        opacity: Double
    ) -> CGFloat {
        let label = Text(text)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(color.opacity(opacity))
        let resolved = context.resolve(label)
        let measured = resolved.measure(in: CGSize(width: 200, height: Self.rowHeight))
        let badgeRect = CGRect(
            x: point.x,
            y: point.y - measured.height / 2 - 1,
            width: measured.width + 4,
            height: measured.height + 2
        )
        context.fill(Path(roundedRect: badgeRect, cornerRadius: 2), with: .color(color.opacity(opacity * 0.22)))
        context.stroke(
            Path(roundedRect: badgeRect, cornerRadius: 2),
            with: .color(color.opacity(opacity * 0.6)),
            lineWidth: 0.5
        )
        context.draw(resolved, at: CGPoint(x: point.x + 2, y: point.y), anchor: .leading)
        return measured.width + 4
    }

    // MARK: - Color / age helpers

    func markerColor(for spot: RemoteSpot) -> Color {
        switch spot.source.lowercased() {
        case "rbn": .cyan
        case "pota": .green
        case "sota": .mint
        case "wwff": .green.opacity(0.85)
        case "cluster": .yellow
        case "dxsummit",
             "dxheat",
             "dxwatch": .orange
        default: .white
        }
    }

    func ageOpacity(for spot: RemoteSpot) -> Double {
        let ageSec = Date().timeIntervalSince(spot.spottedAt)
        if ageSec < 300 {
            return 1.0
        }
        if ageSec < 1_200 {
            return 0.85
        }
        if ageSec < 1_800 {
            return 0.55
        }
        return 0.35
    }

    func ageString(for date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 {
            return "\(secs)s"
        }
        return "\(secs / 60)m"
    }

    func axisStep(forVisibleKHz visibleKHz: Double) -> Double {
        if visibleKHz > 1_000 {
            return 200
        }
        if visibleKHz > 200 {
            return 50
        }
        if visibleKHz > 50 {
            return 10
        }
        if visibleKHz > 20 {
            return 5
        }
        return 2
    }

    func filterHalfWidthKHz(forMode mode: String) -> Double {
        let upper = mode.uppercased()
        if upper.contains("CW") {
            return 0.25
        }
        if upper.contains("FT8") || upper.contains("FT4") || upper.contains("DIGI") || upper.contains("DATA") {
            return 1.5
        }
        if upper.contains("SSB") || upper.contains("USB") || upper.contains("LSB") || upper.contains("AM") {
            return 1.2
        }
        return 1.5
    }

    func modeShortName(_ mode: String) -> String {
        let upper = mode.uppercased()
        if upper.contains("CW") {
            return "CW"
        }
        if upper.contains("FT8") {
            return "FT8"
        }
        if upper.contains("FT4") {
            return "FT4"
        }
        if upper.contains("USB") {
            return "USB"
        }
        if upper.contains("LSB") {
            return "LSB"
        }
        if upper.contains("AM") {
            return "AM"
        }
        return upper.isEmpty ? "?" : String(upper.prefix(4))
    }

    func formatAxisLabel(khz: Double) -> String {
        if khz >= 1_000 {
            return String(format: "%.3f", khz / 1_000)
        }
        return String(format: "%.0f", khz)
    }
}
