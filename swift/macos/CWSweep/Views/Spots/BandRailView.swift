import SwiftUI

// MARK: - BandRailView

/// Right-side rail showing one row per band with spot counts, sparkline density,
/// and age indicator. Click any row to QSY. Replaces the BandSummaryBar chip strip
/// in hybrid layout mode (Variant 4).
struct BandRailView: View {
    // MARK: Internal

    @Environment(SpotAggregator.self) var spotAggregator
    @Environment(RadioManager.self) var radioManager
    @Environment(BandScopeQueryRunner.self) var queryRunner

    @AppStorage("autoXITEnabled") var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") var autoXITOffsetHz = 0
    @AppStorage("bandScopeFilterMode") var filterMode: BandScopeFilterMode = .widgets

    /// Spots restricted to the active SQL allow-list when SQL mode is
    /// on; falls through to all spots in widget mode.
    var visibleSpots: [EnrichedSpot] {
        if filterMode != .widgets, let allowed = queryRunner.allowedSpotIDs {
            return spotAggregator.spots.filter { allowed.contains($0.spot.id) }
        }
        return spotAggregator.spots
    }

    var body: some View {
        VStack(spacing: 0) {
            railHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(BandEdges.hfBands) { band in
                        railRow(for: band)
                        Divider().opacity(0.3)
                    }
                }
            }
            Divider()
            railFooter
        }
        .frame(width: 200)
        .background(.background)
    }

    // MARK: Private

    private var activeBandId: String? {
        let freqKHz = radioManager.frequency * 1_000
        return BandEdges.band(for: freqKHz)?.id
    }

    private var railHeader: some View {
        HStack {
            Text("Bands")
                .font(.system(size: 11, weight: .semibold))

            Spacer()

            let totalSpots = visibleSpots.count
            let totalMults = visibleSpots.filter {
                $0.neededStatus == .newEntity || $0.neededStatus == .newBandSlot
            }.count
            Text("\(totalSpots) / \(totalMults)m")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var railFooter: some View {
        HStack(spacing: 4) {
            Text("⌘1").font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 2).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
            Text("–")
                .font(.caption2).foregroundStyle(.tertiary)
            Text("⌘0").font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 2).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
            Text("band").font(.caption2).foregroundStyle(.tertiary)

            Spacer()

            Text("⇥").font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 2).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
            Text("next").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func railRow(for band: BandEdge) -> some View {
        let stats = bandStats(for: band)
        let isActive = band.id == activeBandId
        let isDead = stats.totalCount == 0 || (stats.lastSpotAge ?? .infinity) > 30 * 60

        return Button {
            tuneToBand(band, stats: stats)
        } label: {
            railRowContent(band: band, stats: stats, isActive: isActive, isDead: isDead)
        }
        .buttonStyle(.plain)
    }

    private func railRowContent(
        band: BandEdge, stats: BandRailStats, isActive: Bool, isDead: Bool
    ) -> some View {
        HStack(spacing: 8) {
            // Band label
            Text(band.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isActive ? Color(nsColor: .systemGreen) : .primary)
                .frame(width: 36, alignment: .leading)

            // Counts + sparkline
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(stats.totalCount)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if stats.multCount > 0 {
                        Text("\(stats.multCount)m")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .systemGreen))
                    }
                    if stats.newCount > 0 {
                        Text("\(stats.newCount)n")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(nsColor: .systemRed))
                    }
                }

                // Sparkline
                sparkline(for: band, stats: stats)
                    .frame(height: 8)
            }

            Spacer()

            // Age indicator
            VStack(spacing: 1) {
                ageDot(stats: stats)
                if let age = stats.lastSpotAge {
                    Text(formatAge(age))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color(nsColor: .systemGreen).opacity(0.10) : .clear)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(Color(nsColor: .systemGreen))
                    .frame(width: 2)
            }
        }
        .opacity(isDead && !isActive ? 0.4 : 1.0)
    }

    private func sparkline(for band: BandEdge, stats: BandRailStats) -> some View {
        Canvas { context, size in
            let bins = 8
            let binWidth = size.width / CGFloat(bins)

            let maxCount = max(1, stats.sparklineBins.max() ?? 1)

            for idx in 0 ..< bins {
                let count = idx < stats.sparklineBins.count ? stats.sparklineBins[idx] : 0
                let height = count > 0 ? max(1, size.height * CGFloat(count) / CGFloat(maxCount)) : 1
                let hasMult = idx < stats.sparklineMultBins.count && stats.sparklineMultBins[idx] > 0
                let color: Color = hasMult
                    ? Color(nsColor: .systemGreen)
                    : Color(nsColor: .systemBlue)
                let opacity: Double = count > 0 ? (hasMult ? 0.9 : 0.6) : 0.1

                let rect = CGRect(
                    x: CGFloat(idx) * binWidth + 0.5,
                    y: size.height - height,
                    width: binWidth - 1,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(color.opacity(opacity))
                )
            }
        }
    }

    private func ageDot(stats: BandRailStats) -> some View {
        Circle()
            .fill(ageDotColor(stats: stats))
            .frame(width: 6, height: 6)
    }

    private func ageDotColor(stats: BandRailStats) -> Color {
        guard let age = stats.lastSpotAge else {
            return Color(nsColor: .systemGray)
        }
        if age < 5 * 60 {
            return Color(nsColor: .systemGreen)
        } // < 5 min
        if age < 15 * 60 {
            return Color(nsColor: .systemYellow)
        } // < 15 min
        return Color(nsColor: .systemGray)
    }

    private func formatAge(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        }
        return "\(Int(seconds / 3_600))h"
    }

    private func tuneToBand(_ band: BandEdge, stats: BandRailStats) {
        // Tune to the freshest spot on this band, or the band center
        let targetFreqMHz: Double = if let freshest = stats.freshestSpot {
            freshest.spot.frequencyMHz
        } else {
            (band.lowerKHz + band.upperKHz) / 2 / 1_000
        }

        Task {
            await radioManager.tuneToSpot(
                frequencyMHz: targetFreqMHz,
                mode: radioManager.mode,
                autoXITEnabled: autoXITEnabled,
                autoXITOffsetHz: autoXITOffsetHz
            )
        }
    }

    // MARK: - Stats

    private func bandStats(for band: BandEdge) -> BandRailStats {
        let spots = visibleSpots.filter {
            $0.spot.frequencyKHz >= band.lowerKHz && $0.spot.frequencyKHz <= band.upperKHz
        }

        var total = 0
        var mults = 0
        var newCount = 0
        var freshest: EnrichedSpot?
        var sparkBins = [Int](repeating: 0, count: 8)
        var sparkMultBins = [Int](repeating: 0, count: 8)

        let binKHz = band.widthKHz / 8.0

        for spot in spots {
            total += 1
            let isMult = spot.neededStatus == .newEntity || spot.neededStatus == .newBandSlot
            if isMult {
                mults += 1
            }
            if spot.neededStatus == .newEntity || spot.neededStatus == .unknown {
                newCount += 1
            }
            if freshest == nil || spot.spot.timestamp > (freshest?.spot.timestamp ?? .distantPast) {
                freshest = spot
            }

            let binIdx = min(7, Int((spot.spot.frequencyKHz - band.lowerKHz) / binKHz))
            sparkBins[binIdx] += 1
            if isMult {
                sparkMultBins[binIdx] += 1
            }
        }

        let lastAge = freshest.map { Date().timeIntervalSince($0.spot.timestamp) }

        return BandRailStats(
            totalCount: total,
            multCount: mults,
            newCount: newCount,
            lastSpotAge: lastAge,
            freshestSpot: freshest,
            sparklineBins: sparkBins,
            sparklineMultBins: sparkMultBins
        )
    }
}

// MARK: - BandRailStats

private struct BandRailStats {
    let totalCount: Int
    let multCount: Int
    let newCount: Int
    let lastSpotAge: TimeInterval?
    let freshestSpot: EnrichedSpot?
    let sparklineBins: [Int]
    let sparklineMultBins: [Int]
}
