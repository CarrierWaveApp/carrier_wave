// Brag Sheet Statistician Section
//
// Professional Statistician Mode section for the brag sheet share card.
// Displays box plots, badges, and distributions computed from QSO snapshots.

import SwiftUI

// MARK: - BragSheetStatisticianData

/// Statistics computed from brag sheet QSO snapshots for the statistician section.
struct BragSheetStatisticianData {
    // MARK: Internal

    let distance: DistanceStatistics?
    let timing: TimingStatistics?
    let bandDistribution: [BandDistribution]
    let modeDistribution: [ModeDistribution]
    let uniqueStates: Int
    let uniqueGrids: Int

    static func compute(
        from snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatisticianData? {
        guard snapshots.count >= 2 else {
            return nil
        }

        let distances = computeDistances(snapshots)
        let intervals = computeIntervals(snapshots)

        return BragSheetStatisticianData(
            distance: DistanceStatistics.compute(from: distances),
            timing: computeTiming(from: intervals, snapshots: snapshots),
            bandDistribution: computeBandDist(snapshots),
            modeDistribution: computeModeDist(snapshots),
            uniqueStates: Set(snapshots.compactMap(\.state)).count,
            uniqueGrids: Set(
                snapshots.compactMap(\.theirGrid)
                    .map { String($0.prefix(4)) }
            ).count
        )
    }

    // MARK: Private

    // MARK: - Private Helpers

    private static func computeDistances(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> [Double] {
        snapshots.compactMap(\.distanceKm)
    }

    private static func computeIntervals(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> [TimeInterval] {
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else {
            return []
        }
        return zip(sorted, sorted.dropFirst()).map {
            $1.timestamp.timeIntervalSince($0.timestamp)
        }
    }

    private static func computeTiming(
        from intervals: [TimeInterval],
        snapshots: [BragSheetQSOSnapshot]
    ) -> TimingStatistics? {
        guard !intervals.isEmpty else {
            return nil
        }
        let sorted = intervals.sorted()
        let count = Double(sorted.count)
        let sum = sorted.reduce(0, +)
        let mean = sum / count
        let variance = sorted.reduce(0.0) {
            $0 + ($1 - mean) * ($1 - mean)
        } / count

        return TimingStatistics(
            meanIntervalSeconds: mean,
            medianIntervalSeconds: percentile(sorted, at: 0.5),
            stdDevIntervalSeconds: sqrt(variance),
            minIntervalSeconds: sorted.first ?? 0,
            p25IntervalSeconds: percentile(sorted, at: 0.25),
            p75IntervalSeconds: percentile(sorted, at: 0.75),
            maxIntervalSeconds: sorted.last ?? 0,
            peak15MinRate: computePeak15MinRate(snapshots)
        )
    }

    private static func computePeak15MinRate(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> Double {
        let timestamps = snapshots.map(\.timestamp).sorted()
        guard timestamps.count >= 2 else {
            return Double(timestamps.count)
        }
        let window: TimeInterval = 15 * 60
        var bestCount = 0
        for (i, start) in timestamps.enumerated() {
            let end = start.addingTimeInterval(window)
            let count = timestamps[i...].prefix(while: { $0 <= end }).count
            bestCount = max(bestCount, count)
        }
        return Double(bestCount)
    }

    private static func computeBandDist(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> [BandDistribution] {
        let total = Double(snapshots.count)
        guard total > 0 else {
            return []
        }
        var counts: [String: Int] = [:]
        for snap in snapshots {
            let normalized = snap.band.uppercased()
            counts[normalized, default: 0] += 1
        }
        return counts.map { band, count in
            BandDistribution(
                band: band, count: count,
                percentage: Double(count) / total * 100
            )
        }.sorted { $0.count > $1.count }
    }

    private static func computeModeDist(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> [ModeDistribution] {
        let total = Double(snapshots.count)
        guard total > 0 else {
            return []
        }
        var counts: [String: Int] = [:]
        for snap in snapshots {
            let canonical = ModeEquivalence.canonicalName(snap.mode)
            counts[canonical, default: 0] += 1
        }
        return counts.map { mode, count in
            ModeDistribution(
                mode: mode, count: count,
                percentage: Double(count) / total * 100
            )
        }.sorted { $0.count > $1.count }
    }

    private static func percentile(
        _ sorted: [Double], at pct: Double
    ) -> Double {
        guard !sorted.isEmpty else {
            return 0
        }
        let index = pct * Double(sorted.count - 1)
        let lower = Int(floor(index))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = index - Double(lower)
        return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
    }
}

// MARK: - BragSheetStatisticianSection

struct BragSheetStatisticianSection: View {
    let stats: BragSheetStatisticianData

    var body: some View {
        VStack(spacing: 8) {
            sectionHeader
            if let distance = stats.distance {
                boxPlotRow("Distance (km)", distance: distance)
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

private extension BragSheetStatisticianSection {
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
            distanceBoxPlot(dist)
        }
    }

    func distanceBoxPlot(_ dist: DistanceStatistics) -> some View {
        let totalWidth: CGFloat = 320
        let range = dist.max - dist.min
        guard range > 0 else {
            return AnyView(
                Text("No variance")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            )
        }

        return AnyView(
            VStack(spacing: 2) {
                boxPlotBars(dist, totalWidth: totalWidth, range: range)
                boxPlotLabels(dist, totalWidth: totalWidth)
            }
        )
    }

    func boxPlotBars(
        _ dist: DistanceStatistics, totalWidth: CGFloat, range: Double
    ) -> some View {
        func xPos(_ value: Double) -> CGFloat {
            CGFloat((value - dist.min) / range) * totalWidth
        }
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: totalWidth, height: 1)
            Rectangle()
                .fill(.purple.opacity(0.5))
                .frame(
                    width: Swift.max(xPos(dist.p75) - xPos(dist.p25), 2),
                    height: 14
                )
                .offset(x: xPos(dist.p25))
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: 14)
                .offset(x: xPos(dist.median))
            Rectangle()
                .fill(.white.opacity(0.5))
                .frame(width: 1, height: 8)
            Rectangle()
                .fill(.white.opacity(0.5))
                .frame(width: 1, height: 8)
                .offset(x: totalWidth - 1)
        }
        .frame(width: totalWidth, height: 14)
    }

    func boxPlotLabels(
        _ dist: DistanceStatistics, totalWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            boxLabel(formatKm(dist.min))
            Spacer()
            boxLabel(formatKm(dist.p25))
            Spacer()
            boxLabel(formatKm(dist.median), bold: true)
            Spacer()
            boxLabel(formatKm(dist.p75))
            Spacer()
            boxLabel(formatKm(dist.max))
        }
        .frame(width: totalWidth)
    }

    func boxLabel(_ text: String, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(
                size: 7, weight: bold ? .bold : .regular,
                design: .monospaced
            ))
            .foregroundStyle(.white.opacity(bold ? 0.9 : 0.5))
    }

    func formatKm(_ km: Double) -> String {
        if km >= 1_000 {
            return String(format: "%.0fk", km / 1_000)
        }
        return String(format: "%.0f", km)
    }

    // MARK: - Badges Row

    var badgesRow: some View {
        HStack(spacing: 6) {
            if let cv = stats.distance?.coefficientOfVariation {
                statBadge(
                    String(format: "%.2f", cv),
                    label: "dist. CV"
                )
            }
        }
    }

    // MARK: - Band Distribution Bar

    var distributionRow: some View {
        Group {
            if !stats.bandDistribution.isEmpty {
                VStack(spacing: 3) {
                    Text("Band Distribution")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.5))
                    bandStackedBar
                    bandLegend
                }
            }
        }
    }

    var bandStackedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(
                    stats.bandDistribution.prefix(6),
                    id: \.band
                ) { item in
                    let width = geo.size.width
                        * CGFloat(item.percentage / 100)
                    Rectangle()
                        .fill(bandColor(for: item.band))
                        .frame(width: max(width, 2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 14)
        .padding(.horizontal, 4)
    }

    var bandLegend: some View {
        HStack(spacing: 6) {
            ForEach(
                stats.bandDistribution.prefix(6),
                id: \.band
            ) { item in
                HStack(spacing: 2) {
                    Circle()
                        .fill(bandColor(for: item.band))
                        .frame(width: 5, height: 5)
                    Text("\(item.band)")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(String(format: "%.0f%%", item.percentage))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    func bandColor(for band: String) -> Color {
        let hfBands: [(String, Color)] = [
            ("160M", Color(red: 0.8, green: 0.2, blue: 0.2)),
            ("80M", Color(red: 0.9, green: 0.4, blue: 0.1)),
            ("60M", Color(red: 0.95, green: 0.55, blue: 0.1)),
            ("40M", Color(red: 0.95, green: 0.75, blue: 0.1)),
            ("30M", Color(red: 0.7, green: 0.85, blue: 0.1)),
            ("20M", Color(red: 0.3, green: 0.8, blue: 0.2)),
            ("17M", Color(red: 0.1, green: 0.75, blue: 0.5)),
            ("15M", Color(red: 0.1, green: 0.7, blue: 0.8)),
            ("12M", Color(red: 0.2, green: 0.5, blue: 0.9)),
            ("10M", Color(red: 0.4, green: 0.3, blue: 0.9)),
            ("6M", Color(red: 0.6, green: 0.2, blue: 0.8)),
            ("2M", Color(red: 0.8, green: 0.2, blue: 0.6)),
        ]
        let upper = band.uppercased()
        if let match = hfBands.first(where: { $0.0 == upper }) {
            return match.1
        }
        return Color.purple.opacity(0.7)
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
}
