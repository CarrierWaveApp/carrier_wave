import CarrierWaveCore
import SwiftUI

// MARK: - SpotMarker

/// Lightweight spot data for VerticalBandMapView input.
struct SpotMarker: Identifiable {
    let id = UUID()
    let frequencyMHz: Double
    let callsign: String
    let ageMinutes: Int // 0–30
}

// MARK: - VerticalBandMapView

/// Canvas-rendered vertical band map showing spots, band plan regions, and a frequency suggestion.
struct VerticalBandMapView: View {
    // MARK: Internal

    static let labelWidth: CGFloat = 44
    static let densityWidth: CGFloat = 8
    static let headerHeight: CGFloat = 36
    static let footerHeight: CGFloat = 24

    let band: String
    let spots: [SpotMarker]
    let suggestion: FrequencySuggestion?

    var body: some View {
        VStack(spacing: 0) {
            headerView
            GeometryReader { geo in
                Canvas { ctx, size in
                    let segs = bandSegments
                    let (minFreq, maxFreq) = bandFrequencyRange(segments: segs)
                    guard maxFreq > minFreq else {
                        return
                    }
                    drawBandPlanRegions(ctx: ctx, size: size, segments: segs, minFreq: minFreq, maxFreq: maxFreq)
                    drawDensityStrip(ctx: ctx, size: size, minFreq: minFreq, maxFreq: maxFreq)
                    drawYAxisLabels(ctx: ctx, size: size, minFreq: minFreq, maxFreq: maxFreq)
                    drawSuggestionBand(ctx: ctx, size: size, minFreq: minFreq, maxFreq: maxFreq)
                    drawSpotMarkers(ctx: ctx, size: size, minFreq: minFreq, maxFreq: maxFreq)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            footerView
        }
    }

    // MARK: Private

    private var bandSegments: [BandSegment] {
        BandPlan.segments.filter { $0.band == band }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(band.uppercased())
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                Spacer()
                Text("Last 30 min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            let (minFreq, maxFreq) = bandFrequencyRange(segments: bandSegments)
            if maxFreq > minFreq {
                Text("\(String(format: "%.3f", minFreq))–\(String(format: "%.3f", maxFreq)) MHz")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: Self.headerHeight)
    }

    private var footerView: some View {
        HStack {
            Text("\(spots.count) spot\(spots.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("RBN + POTA + Cluster")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.footerHeight)
    }
}

// MARK: - Frequency Helpers

extension VerticalBandMapView {
    func bandFrequencyRange(segments: [BandSegment]) -> (Double, Double) {
        let minFreq = segments.map(\.startMHz).min() ?? 0
        let maxFreq = segments.map(\.endMHz).max() ?? 0
        return (minFreq, maxFreq)
    }

    func yPos(freq: Double, minFreq: Double, maxFreq: Double, height: CGFloat) -> CGFloat {
        let range = maxFreq - minFreq
        guard range > 0 else {
            return 0
        }
        // Top = high frequency, bottom = low frequency (typical band map convention)
        let fraction = (maxFreq - freq) / range
        return fraction * height
    }

    func spotColor(ageMinutes: Int) -> Color {
        if ageMinutes <= 10 {
            .green
        } else if ageMinutes <= 20 {
            .yellow
        } else {
            .red
        }
    }
}

// MARK: - Canvas Drawing

extension VerticalBandMapView {
    func drawBandPlanRegions(
        ctx: GraphicsContext, size: CGSize,
        segments: [BandSegment], minFreq: Double, maxFreq: Double
    ) {
        let plotX = Self.labelWidth
        let plotW = size.width - plotX

        var drawn: Set<String> = []
        for seg in segments {
            let key = "\(seg.startMHz)-\(seg.endMHz)"
            guard !drawn.contains(key) else {
                continue
            }
            drawn.insert(key)

            let yTop = yPos(freq: seg.endMHz, minFreq: minFreq, maxFreq: maxFreq, height: size.height)
            let yBot = yPos(freq: seg.startMHz, minFreq: minFreq, maxFreq: maxFreq, height: size.height)
            let rect = CGRect(x: plotX, y: yTop, width: plotW, height: yBot - yTop)

            let isExtra = seg.minimumLicense == .extra
            let color: Color = isExtra ? .purple.opacity(0.12) : .purple.opacity(0.06)
            ctx.fill(Path(rect), with: .color(color))
        }
    }

    func drawDensityStrip(
        ctx: GraphicsContext, size: CGSize,
        minFreq: Double, maxFreq: Double
    ) {
        let binCount = 20
        let binSize = (maxFreq - minFreq) / Double(binCount)
        guard binSize > 0 else {
            return
        }

        var bins = [Int](repeating: 0, count: binCount)
        for spot in spots {
            let binIdx = Int((spot.frequencyMHz - minFreq) / binSize)
            let clamped = max(0, min(binCount - 1, binIdx))
            bins[clamped] += 1
        }

        let maxBin = bins.max() ?? 1
        let densityW = Self.densityWidth

        for idx in 0 ..< binCount {
            guard bins[idx] > 0 else {
                continue
            }
            let density = CGFloat(bins[idx]) / CGFloat(max(maxBin, 1))
            let freqTop = maxFreq - Double(idx) * binSize
            let freqBot = freqTop - binSize
            let yTop = yPos(freq: freqTop, minFreq: minFreq, maxFreq: maxFreq, height: size.height)
            let yBot = yPos(freq: freqBot, minFreq: minFreq, maxFreq: maxFreq, height: size.height)
            let rect = CGRect(x: Self.labelWidth, y: yTop, width: densityW, height: yBot - yTop)
            ctx.fill(Path(rect), with: .color(.green.opacity(Double(density) * 0.5)))
        }
    }

    func drawYAxisLabels(
        ctx: GraphicsContext, size: CGSize,
        minFreq: Double, maxFreq: Double
    ) {
        let range = maxFreq - minFreq
        guard range > 0 else {
            return
        }

        let tickStep = axisTickStep(range: range)
        var freq = (minFreq / tickStep).rounded(.up) * tickStep

        while freq <= maxFreq {
            let yp = yPos(freq: freq, minFreq: minFreq, maxFreq: maxFreq, height: size.height)

            var tick = Path()
            tick.move(to: CGPoint(x: Self.labelWidth - 3, y: yp))
            tick.addLine(to: CGPoint(x: Self.labelWidth, y: yp))
            ctx.stroke(tick, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)

            let label = Text(String(format: "%.3f", freq))
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.secondary)
            ctx.draw(
                ctx.resolve(label),
                at: CGPoint(x: Self.labelWidth - 5, y: yp),
                anchor: .trailing
            )
            freq += tickStep
        }
    }

    func drawSuggestionBand(
        ctx: GraphicsContext, size: CGSize,
        minFreq: Double, maxFreq: Double
    ) {
        guard let suggestion else {
            return
        }
        let halfBandMHz = 0.007 // ~7 kHz half-band for highlight
        let topFreq = suggestion.frequencyMHz + halfBandMHz
        let botFreq = suggestion.frequencyMHz - halfBandMHz
        let yTop = yPos(freq: topFreq, minFreq: minFreq, maxFreq: maxFreq, height: size.height)
        let yBot = yPos(freq: botFreq, minFreq: minFreq, maxFreq: maxFreq, height: size.height)
        let bandH: CGFloat = max(14, yBot - yTop)
        let plotX = Self.labelWidth
        let plotW = size.width - plotX
        let rect = CGRect(x: plotX, y: yTop, width: plotW, height: bandH)

        ctx.fill(Path(rect), with: .color(.green.opacity(0.18)))
        ctx.stroke(
            Path(roundedRect: rect, cornerRadius: 2),
            with: .color(.green.opacity(0.6)),
            lineWidth: 1
        )

        let label = Text("QSY")
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(.green)
        ctx.draw(
            ctx.resolve(label),
            at: CGPoint(x: plotX + plotW - 4, y: yTop + bandH / 2),
            anchor: .trailing
        )
    }

    func drawSpotMarkers(
        ctx: GraphicsContext, size: CGSize,
        minFreq: Double, maxFreq: Double
    ) {
        let plotX = Self.labelWidth + Self.densityWidth + 2
        let plotW = size.width - plotX

        for spot in spots {
            guard spot.frequencyMHz >= minFreq, spot.frequencyMHz <= maxFreq else {
                continue
            }
            let yp = yPos(freq: spot.frequencyMHz, minFreq: minFreq, maxFreq: maxFreq, height: size.height)
            let color = spotColor(ageMinutes: spot.ageMinutes)
            let opacity = max(0.3, 1.0 - Double(spot.ageMinutes) / 30.0 * 0.7)

            var line = Path()
            line.move(to: CGPoint(x: plotX, y: yp))
            line.addLine(to: CGPoint(x: plotX + plotW * 0.25, y: yp))
            ctx.stroke(line, with: .color(color.opacity(opacity)), lineWidth: 1)

            let label = Text(spot.callsign)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(color.opacity(opacity))
            ctx.draw(
                ctx.resolve(label),
                at: CGPoint(x: plotX + plotW * 0.25 + 3, y: yp),
                anchor: .leading
            )
        }
    }

    func axisTickStep(range: Double) -> Double {
        if range > 5.0 {
            1.0
        } else if range > 1.0 {
            0.5
        } else if range > 0.5 {
            0.1
        } else {
            0.05
        }
    }
}
