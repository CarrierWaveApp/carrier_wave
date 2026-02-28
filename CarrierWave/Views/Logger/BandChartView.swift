// Band Chart View
//
// Visual ARRL-style band allocation chart with license class
// and mode zone display. Scrollable, pinch-to-zoom, with tick marks.
// Tap a zone to select its center frequency.

import CarrierWaveCore
import SwiftUI

// MARK: - BandChartDisplayMode

enum BandChartDisplayMode: String, CaseIterable {
    case byClass = "By Class"
    case byMode = "By Mode"
}

// MARK: - BandChartView

/// Visual band chart showing license allocations or mode usage zones
struct BandChartView: View {
    // MARK: Internal

    let chartData: BandChartData
    let displayMode: BandChartDisplayMode
    let userLicenseClass: LicenseClass
    let onSelectFrequency: (Double) -> Void

    var body: some View {
        if chartData.isChannelized {
            channelizedChart
        } else {
            zoomableScrollChart
        }
    }

    // MARK: Private

    @State private var zoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 8.0
    private let labelWidth: CGFloat = 22

    private var barHeight: CGFloat {
        20
    }

    /// License classes that have at least one bar on this band
    private var visibleClasses: [LicenseClass] {
        let allClasses: [LicenseClass] = [.extra, .general, .technician]
        return allClasses.filter { lc in
            chartData.classBars.contains { $0.licenseClass == lc }
        }
    }

    private var chartFrameHeight: CGFloat {
        switch displayMode {
        case .byClass:
            let rows = CGFloat(visibleClasses.count)
            return rows * barHeight + max(rows - 1, 0) * 2 + 24 + 4
        case .byMode:
            return 52
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let proposed = baseZoom * value.magnification
                zoom = min(max(proposed, minZoom), maxZoom)
            }
            .onEnded { _ in
                baseZoom = zoom
            }
    }

    // MARK: - Channelized (60m)

    private var channelizedChart: some View {
        HStack(spacing: 12) {
            ForEach(
                Array(chartData.channelFrequencies.enumerated()),
                id: \.offset
            ) { idx, freq in
                Button {
                    onSelectFrequency(freq)
                } label: {
                    VStack(spacing: 2) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                        Text("Ch \(idx + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Zoomable Scroll Chart

    private var zoomableScrollChart: some View {
        GeometryReader { outer in
            let fixedLabel = displayMode == .byClass ? labelWidth : 0
            let chartAreaWidth = outer.size.width - fixedLabel
            let innerWidth = chartAreaWidth * zoom

            HStack(alignment: .top, spacing: 0) {
                if displayMode == .byClass {
                    classLabelColumn
                        .frame(width: labelWidth)
                }

                ScrollView(.horizontal, showsIndicators: zoom > 1) {
                    chartCanvas(width: innerWidth)
                        .frame(width: innerWidth)
                }
            }
        }
        .frame(height: chartFrameHeight)
        .simultaneousGesture(magnifyGesture)
    }

    // MARK: - Fixed Class Labels

    private var classLabelColumn: some View {
        VStack(spacing: 2) {
            ForEach(visibleClasses, id: \.self) { licenseClass in
                let isUserClass = licenseClass == userLicenseClass
                let hasAccess = userHasAccess(to: licenseClass)
                Text(licenseClass.abbreviation)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: labelWidth, height: barHeight)
                    .opacity(isUserClass ? 1.0 : (hasAccess ? 0.6 : 0.35))
            }
        }
    }

    // MARK: - Chart Canvas

    private func chartCanvas(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            chartBars(width: width)
            tickRuler(width: width)
        }
    }

    // MARK: - Chart Bars

    @ViewBuilder
    private func chartBars(width: CGFloat) -> some View {
        switch displayMode {
        case .byClass:
            classChart(width: width)
        case .byMode:
            modeChart(width: width)
        }
    }

    private func classChart(width: CGFloat) -> some View {
        VStack(spacing: 2) {
            ForEach(visibleClasses, id: \.self) { licenseClass in
                classRow(licenseClass, width: width)
            }
        }
    }

    private func classRow(
        _ licenseClass: LicenseClass, width: CGFloat
    ) -> some View {
        let bars = chartData.classBars.filter {
            $0.licenseClass == licenseClass
        }
        let isUserClass = licenseClass == userLicenseClass
        let hasAccess = userHasAccess(to: licenseClass)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray5))
                .frame(width: width, height: barHeight)

            ForEach(bars) { bar in
                allocationBar(bar, totalWidth: width, licenseClass: licenseClass)
            }
        }
        .frame(width: width, height: barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .opacity(isUserClass ? 1.0 : (hasAccess ? 0.6 : 0.35))
    }

    private func allocationBar(
        _ bar: ClassAllocationBar,
        totalWidth: CGFloat,
        licenseClass: LicenseClass
    ) -> some View {
        let pos = barPosition(
            start: bar.startMHz, end: bar.endMHz, totalWidth: totalWidth
        )
        return Rectangle()
            .fill(licenseColor(licenseClass))
            .frame(width: max(pos.width, 2), height: barHeight)
            .contentShape(Rectangle().size(width: max(pos.width, 44), height: 44))
            .position(x: pos.x + pos.width / 2, y: barHeight / 2)
            .onTapGesture {
                onSelectFrequency((bar.startMHz + bar.endMHz) / 2)
            }
    }

    private func modeChart(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray5))
                .frame(width: width, height: 24)

            ForEach(chartData.modeZones) { zone in
                modeZoneBar(zone, totalWidth: width)
            }
        }
        .frame(width: width, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func modeZoneBar(
        _ zone: ModeZoneBar, totalWidth: CGFloat
    ) -> some View {
        let pos = barPosition(
            start: zone.startMHz, end: zone.endMHz, totalWidth: totalWidth
        )
        return Rectangle()
            .fill(modeColor(zone.usage))
            .frame(width: max(pos.width, 2), height: 24)
            .contentShape(Rectangle().size(width: max(pos.width, 44), height: 44))
            .position(x: pos.x + pos.width / 2, y: 12)
            .onTapGesture {
                onSelectFrequency((zone.startMHz + zone.endMHz) / 2)
            }
    }

    // MARK: - Tick Ruler (Canvas)

    private func tickRuler(width: CGFloat) -> some View {
        let ticks = computeTicks()
        let bandSpan = chartData.bandEndMHz - chartData.bandStartMHz

        return Canvas { context, size in
            let tickColor = Color(.systemGray3)
            let labelColor = Color(.secondaryLabel)

            for freq in ticks {
                let frac = (freq - chartData.bandStartMHz) / bandSpan
                let x = frac * size.width

                // Tick line
                let tickPath = Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: 6))
                }
                context.stroke(
                    tickPath, with: .color(tickColor), lineWidth: 1
                )

                // Label
                let label = formatTickFreq(freq)
                let text = Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(labelColor)
                let resolved = context.resolve(text)
                let textSize = resolved.measure(in: size)
                let labelX = min(
                    max(x - textSize.width / 2, 0),
                    size.width - textSize.width
                )
                context.draw(
                    resolved,
                    at: CGPoint(x: labelX + textSize.width / 2, y: 14)
                )
            }
        }
        .frame(width: width, height: 24)
    }

    // MARK: - Tick Computation

    private func computeTicks() -> [Double] {
        let span = chartData.bandEndMHz - chartData.bandStartMHz
        guard span > 0 else {
            return []
        }

        let step = tickStep(for: span)
        let start = chartData.bandStartMHz
        let end = chartData.bandEndMHz

        // Regular evenly-spaced ticks
        var regularTicks: [Double] = []
        let firstTick = (start / step).rounded(.up) * step
        var freq = firstTick
        while freq <= end + step * 0.01 {
            regularTicks.append(freq)
            freq += step
        }

        // Always include segment edges
        let edges = Set(chartData.segmentEdges)

        // Drop regular ticks that are too close to an edge
        let minSep = span * 0.02
        var combined = edges
        for tick in regularTicks {
            let tooClose = edges.contains { abs(tick - $0) < minSep }
            if !tooClose {
                combined.insert(tick)
            }
        }

        return combined.sorted()
    }

    private func tickStep(for span: Double) -> Double {
        let targetTicks = 4.0 * Double(zoom)
        let rawStep = span / targetTicks
        let magnitude = pow(10, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let niceStep: Double =
            if normalized <= 1.5 {
                1
            } else if normalized <= 3.5 {
                2.5
            } else if normalized <= 7.5 {
                5
            } else {
                10
            }
        return niceStep * magnitude
    }

    private func formatTickFreq(_ freq: Double) -> String {
        if freq >= 100 {
            return String(format: "%.0f", freq)
        } else if freq.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", freq)
        }
        return String(format: "%.3f", freq)
    }

    // MARK: - Helpers

    private func barPosition(
        start: Double, end: Double, totalWidth: CGFloat
    ) -> (x: CGFloat, width: CGFloat) {
        let bandSpan = chartData.bandEndMHz - chartData.bandStartMHz
        guard bandSpan > 0 else {
            return (0, totalWidth)
        }

        let startFrac = (start - chartData.bandStartMHz) / bandSpan
        let endFrac = (end - chartData.bandStartMHz) / bandSpan
        let xPos = CGFloat(startFrac) * totalWidth
        let width = CGFloat(endFrac - startFrac) * totalWidth
        return (xPos, width)
    }

    private func userHasAccess(to licenseClass: LicenseClass) -> Bool {
        let order: [LicenseClass] = [.technician, .general, .extra]
        let userIdx = order.firstIndex(of: userLicenseClass) ?? 0
        let targetIdx = order.firstIndex(of: licenseClass) ?? 0
        return userIdx >= targetIdx
    }
}

// MARK: - Colors

extension BandChartView {
    func licenseColor(_ license: LicenseClass) -> Color {
        switch license {
        case .technician: .green
        case .general: .blue
        case .extra: .purple
        }
    }

    func modeSetColor(_ modes: Set<String>) -> Color {
        let hasPhone = modes.contains("SSB") || modes.contains("PHONE")
        let hasCW = modes.contains("CW")
        let hasData = modes.contains("DATA")

        if hasPhone {
            return .green
        }
        if hasCW, hasData {
            return .teal
        }
        if hasCW {
            return .blue
        }
        if hasData {
            return .orange
        }
        if modes.contains("FM") {
            return .cyan
        }
        if modes.contains("AM") {
            return .yellow
        }
        return .gray
    }

    func modeColor(_ usage: UsageZone.Usage) -> Color {
        switch usage {
        case .cw: .blue
        case .digital: .orange
        case .cwAndDigital: .teal
        case .phone: .green
        case .am: .yellow
        case .fm: .cyan
        }
    }
}
