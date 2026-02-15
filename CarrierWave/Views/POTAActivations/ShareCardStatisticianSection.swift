// Share Card Statistician Section
//
// Extra brag sheet section shown when Professional Statistician Mode is on.
// Displays advanced statistics, distribution data, and tongue-in-cheek badges.

import SwiftUI

// MARK: - ShareCardStatisticianSection

struct ShareCardStatisticianSection: View {
    let stats: ActivationStatistics

    var body: some View {
        VStack(spacing: 8) {
            sectionHeader
            if let distance = stats.distance {
                boxPlotRow("Distance (km)", distance: distance)
            }
            if let timing = stats.timing {
                timingBoxPlotRow(timing)
            }
            badgesRow
            distributionRow
            modesRow
            entityRow
            significanceBadge
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color.purple.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

// MARK: - Subviews

private extension ShareCardStatisticianSection {
    var sectionHeader: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.caption2)
            Text("PROFESSIONAL STATISTICIAN MODE")
                .font(.caption2)
                .fontWeight(.heavy)
                .tracking(1)
        }
        .foregroundStyle(.white.opacity(0.6))
    }

    // MARK: - Box Plots

    func boxPlotRow(
        _ title: String,
        distance dist: DistanceStatistics
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.5))
            genericBoxPlot(
                min: dist.min, p25: dist.p25,
                median: dist.median, p75: dist.p75, max: dist.max
            )
        }
    }

    func timingBoxPlotRow(_ timing: TimingStatistics) -> some View {
        VStack(spacing: 2) {
            Text("Time Between QSOs (s)")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.5))
            genericBoxPlot(
                min: timing.minIntervalSeconds,
                p25: timing.p25IntervalSeconds,
                median: timing.medianIntervalSeconds,
                p75: timing.p75IntervalSeconds,
                max: timing.maxIntervalSeconds
            )
        }
    }

    func genericBoxPlot(
        min: Double, p25: Double, median: Double,
        p75: Double, max: Double
    ) -> some View {
        let totalWidth: CGFloat = 320
        let range = max - min
        guard range > 0 else {
            return AnyView(
                Text("No variance")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            )
        }

        func xPos(_ value: Double) -> CGFloat {
            CGFloat((value - min) / range) * totalWidth
        }

        return AnyView(
            ZStack(alignment: .leading) {
                // Whisker line: min to max
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: totalWidth, height: 1)
                // IQR box: p25 to p75
                Rectangle()
                    .fill(.purple.opacity(0.5))
                    .frame(
                        width: Swift.max(xPos(p75) - xPos(p25), 2),
                        height: 14
                    )
                    .offset(x: xPos(p25))
                // Median line
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: 14)
                    .offset(x: xPos(median))
                // Min/max caps
                Rectangle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 1, height: 8)
                Rectangle()
                    .fill(.white.opacity(0.5))
                    .frame(width: 1, height: 8)
                    .offset(x: totalWidth - 1)
            }
            .frame(width: totalWidth, height: 14)
        )
    }

    // MARK: - Badges Row

    var badgesRow: some View {
        HStack(spacing: 6) {
            if let timing = stats.timing {
                statBadge(
                    String(format: "%.0f QSOs", timing.peak15MinRate),
                    label: "best 15-min"
                )
                statBadge(
                    formatInterval(timing.medianIntervalSeconds),
                    label: "p50 interval"
                )
            }
            if let cv = stats.distance?.coefficientOfVariation {
                statBadge(
                    String(format: "%.2f", cv),
                    label: "dist. CV"
                )
            }
        }
    }

    // MARK: - Distribution Row

    var distributionRow: some View {
        HStack(spacing: 12) {
            if !stats.bandDistribution.isEmpty {
                distributionColumn(
                    title: "Bands",
                    items: stats.bandDistribution.prefix(4).map {
                        ($0.band, $0.percentage)
                    }
                )
            }
        }
    }

    // MARK: - Modes Row

    var modesRow: some View {
        Group {
            if !stats.modeDistribution.isEmpty {
                HStack(spacing: 6) {
                    Text("Modes")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.5))
                    ForEach(stats.modeDistribution, id: \.mode) { item in
                        Text("\(item.mode) \(item.count)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
    }

    func distributionColumn(
        title: String,
        items: [(String, Double)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.5))
            ForEach(items, id: \.0) { name, pct in
                HStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 9, design: .monospaced))
                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    // MARK: - Entity Row

    var entityRow: some View {
        HStack(spacing: 12) {
            if stats.uniqueStates > 0 {
                entityBadge(
                    "\(stats.uniqueStates)",
                    label: stats.uniqueStates == 1 ? "state" : "states"
                )
            }
            if stats.uniqueGrids > 0 {
                entityBadge(
                    "\(stats.uniqueGrids)",
                    label: stats.uniqueGrids == 1 ? "grid" : "grids"
                )
            }
        }
    }

    // MARK: - Significance Badge

    var significanceBadge: some View {
        Text("p < 0.05*")
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
            .italic()
    }

    // MARK: - Helpers

    func statBadge(_ value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 7))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func entityBadge(_ value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 9))
        }
        .foregroundStyle(.white.opacity(0.8))
    }

    func formatInterval(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m\(secs)s"
    }
}
