import SwiftUI

// MARK: - GridBandOverviewView

/// TradingView-inspired grid of band cells (Variant 3).
/// A 4×3 grid showing spot density histograms per band. Click a cell to expand
/// into the main scope view on the right side.
struct GridBandOverviewView: View {
    // MARK: Internal

    @Environment(SpotAggregator.self) var spotAggregator
    @Environment(RadioManager.self) var radioManager
    @Environment(SelectionState.self) var selectionState
    @Environment(BandScopeQueryRunner.self) var queryRunner

    @AppStorage("bandScopeMaxAgeMinutes") var maxAgeMinutes: Int = 30
    @AppStorage("bandScopeFilterMode") var filterMode: BandScopeFilterMode = .widgets
    @AppStorage("autoXITEnabled") var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") var autoXITOffsetHz = 0

    /// Spot pool stats are derived from. In SQL mode this is restricted
    /// to the active query's allow-list so cell counts / mult tallies /
    /// histograms reflect what the user is actually filtering for. The
    /// per-band frequency clip happens downstream in `cellStats`.
    var visibleSpots: [EnrichedSpot] {
        if filterMode != .widgets, let allowed = queryRunner.allowedSpotIDs {
            return spotAggregator.spots.filter { allowed.contains($0.spot.id) }
        }
        return spotAggregator.spots
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                // Grid (left)
                gridPanel
                    .frame(width: 500)
                Divider()
                // Expanded scope (right)
                ContestBandScopeView(showSummaryBar: false)
            }
            Divider()
            bottomBar
        }
    }

    // MARK: Private

    @State private var expandedBandId: String = "20m"

    private var activeBandId: String? {
        let freqKHz = radioManager.frequency * 1_000
        return BandEdges.band(for: freqKHz)?.id
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Band Grid Overview")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Text("VFO")
                .font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.1f", radioManager.frequency * 1_000))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(nsColor: .systemRed))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(nsColor: .systemRed), lineWidth: 1.5)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var gridPanel: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(BandEdges.hfBands) { band in
                    gridCell(for: band)
                }
                // "All HF" summary cell
                allBandsSummaryCell
            }
            .padding(12)
        }
    }

    private var allBandsSummaryCell: some View {
        let totalSpots = visibleSpots.count
        let totalMults = visibleSpots.filter {
            $0.neededStatus == .newEntity || $0.neededStatus == .newBandSlot
        }.count
        let totalNew = visibleSpots.filter {
            $0.neededStatus == .newEntity || $0.neededStatus == .unknown
        }.count

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("All HF")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("summary")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                statLabel("\(totalSpots)", label: "spots")
                statLabel("\(totalMults)", label: "mults", color: Color(nsColor: .systemGreen))
                statLabel("\(totalNew)", label: "new", color: Color(nsColor: .systemRed))
            }
        }
        .padding(8)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.3),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
        )
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Group {
                Text("←→↑↓ cell")
                Text("⏎ expand")
                Text("⇧⏎ QSY")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Spacer()

            let total = visibleSpots.count
            let mults = visibleSpots.filter {
                $0.neededStatus == .newEntity || $0.neededStatus == .newBandSlot
            }.count
            Text("\(total) spots · \(mults) mults · \(BandEdges.hfBands.count) bands")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func gridCell(for band: BandEdge) -> some View {
        let stats = cellStats(for: band)
        let isActive = band.id == activeBandId
        let isExpanded = band.id == expandedBandId
        let isDead = stats.totalCount == 0

        return Button {
            expandedBandId = band.id
        } label: {
            gridCellContent(
                band: band, stats: stats,
                isActive: isActive, isExpanded: isExpanded, isDead: isDead
            )
        }
        .buttonStyle(.plain)
    }

    private func gridCellContent(
        band: BandEdge, stats: GridCellStats,
        isActive: Bool, isExpanded: Bool, isDead: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Text(band.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isActive ? Color(nsColor: .systemGreen) : .primary)
                Spacer()
                if let age = stats.lastSpotAge {
                    Text(formatAge(age))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(age < 300 ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
                }
            }

            // Stats
            HStack(spacing: 8) {
                statLabel("\(stats.totalCount)", label: stats.totalCount == 1 ? "spot" : "spots")
                if stats.multCount > 0 {
                    statLabel("\(stats.multCount)", label: stats.multCount == 1 ? "mult" : "mults",
                              color: Color(nsColor: .systemGreen))
                }
                if stats.newCount > 0 {
                    statLabel("\(stats.newCount)", label: "new",
                              color: Color(nsColor: .systemRed))
                }
            }

            // Density histogram
            densityHistogram(stats: stats)
                .frame(height: 28)

            // Heat strip
            heatStrip(stats: stats)
                .frame(height: 4)
        }
        .padding(8)
        .background(
            isActive
                ? Color(nsColor: .systemGreen).opacity(0.08)
                : Color(nsColor: .controlBackgroundColor).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isExpanded
                        ? Color(nsColor: .systemGreen)
                        : Color(nsColor: .separatorColor),
                    lineWidth: isExpanded ? 2 : 1
                )
        )
        .opacity(isDead ? 0.5 : 1.0)
    }
}

// MARK: - Cell Components

extension GridBandOverviewView {
    func statLabel(_ value: String, label: String, color: Color = .primary) -> some View {
        HStack(spacing: 2) {
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    func densityHistogram(stats: GridCellStats) -> some View {
        Canvas { context, size in
            let bins = stats.histogramBins
            let maxVal = max(1, bins.max() ?? 1)
            let binWidth = size.width / CGFloat(bins.count)

            for (idx, count) in bins.enumerated() {
                let height = count > 0
                    ? max(1, size.height * CGFloat(count) / CGFloat(maxVal))
                    : 0
                let isMult = idx < stats.histogramMultBins.count && stats.histogramMultBins[idx] > 0
                let isNew = idx < stats.histogramNewBins.count && stats.histogramNewBins[idx] > 0

                let color = if isMult {
                    Color(nsColor: .systemGreen)
                } else if isNew {
                    Color(nsColor: .systemRed)
                } else {
                    Color(nsColor: .systemBlue)
                }

                let rect = CGRect(
                    x: CGFloat(idx) * binWidth + 0.5,
                    y: size.height - height,
                    width: binWidth - 1,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(color.opacity(isMult ? 0.85 : 0.55))
                )
            }
        }
    }

    func heatStrip(stats: GridCellStats) -> some View {
        HStack(spacing: 1) {
            ForEach(0 ..< 6, id: \.self) { idx in
                let opacity = heatOpacity(index: idx, stats: stats)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(nsColor: .systemGreen).opacity(opacity))
            }
        }
    }

    private func heatOpacity(index: Int, stats: GridCellStats) -> Double {
        let windowMinutes = [1.0, 2.0, 5.0, 10.0, 20.0, 30.0]
        guard index < windowMinutes.count else {
            return 0.1
        }
        guard let age = stats.lastSpotAge else {
            return 0.1
        }
        if age / 60 < windowMinutes[index] {
            return 0.85
        }
        return 0.1
    }

    func formatAge(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        }
        return "\(Int(seconds / 3_600))h"
    }

    func cellStats(for band: BandEdge) -> GridCellStats {
        let spots = visibleSpots.filter {
            $0.spot.frequencyKHz >= band.lowerKHz && $0.spot.frequencyKHz <= band.upperKHz
        }

        var total = 0
        var mults = 0
        var newCount = 0
        var freshest: Date?
        let binCount = 8
        var histBins = [Int](repeating: 0, count: binCount)
        var histMultBins = [Int](repeating: 0, count: binCount)
        var histNewBins = [Int](repeating: 0, count: binCount)
        let binKHz = band.widthKHz / Double(binCount)

        for spot in spots {
            total += 1
            let isMult = spot.neededStatus == .newEntity || spot.neededStatus == .newBandSlot
            if isMult {
                mults += 1
            }
            if spot.neededStatus == .newEntity || spot.neededStatus == .unknown {
                newCount += 1
            }
            if freshest == nil || spot.spot.timestamp > (freshest ?? .distantPast) {
                freshest = spot.spot.timestamp
            }

            let binIdx = min(binCount - 1,
                             Int((spot.spot.frequencyKHz - band.lowerKHz) / binKHz))
            histBins[binIdx] += 1
            if isMult {
                histMultBins[binIdx] += 1
            }
            if spot.neededStatus == .newEntity {
                histNewBins[binIdx] += 1
            }
        }

        let lastAge = freshest.map { Date().timeIntervalSince($0) }

        return GridCellStats(
            totalCount: total, multCount: mults, newCount: newCount,
            lastSpotAge: lastAge,
            histogramBins: histBins, histogramMultBins: histMultBins,
            histogramNewBins: histNewBins
        )
    }
}

// MARK: - GridCellStats

struct GridCellStats {
    let totalCount: Int
    let multCount: Int
    let newCount: Int
    let lastSpotAge: TimeInterval?
    let histogramBins: [Int]
    let histogramMultBins: [Int]
    let histogramNewBins: [Int]
}
