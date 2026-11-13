import SwiftUI

// MARK: - BandSummaryBar

/// Compact bar showing spot/new/mult counts for the current band.
/// Inspired by Win-Test's "is it worth staying on this band?" decision support.
struct BandSummaryBar: View {
    // MARK: Internal

    @Environment(SpotAggregator.self) var spotAggregator

    let selectedBandId: String
    let enabledSources: Set<SpotSource>

    var body: some View {
        HStack(spacing: 12) {
            bandStatView(label: "Spots", count: stats.totalCount, color: .secondary)
            bandStatView(label: "New", count: stats.newCount, color: Color(nsColor: .systemBlue))
            bandStatView(label: "Mults", count: stats.multCount, color: Color(nsColor: .systemGreen))

            if pillsFit {
                Divider().frame(height: 12)
                crossBandPills
            }

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.background)
        .overlay {
            // Measure pill width off-screen
            crossBandPills
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    pillsWidth = newWidth
                }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            barWidth = newWidth
        }
    }

    // MARK: Private

    @State private var barWidth: CGFloat = 0
    @State private var pillsWidth: CGFloat = 0

    /// Pills fit if the bar has enough room beyond the stats (~200px)
    private var pillsFit: Bool {
        barWidth > pillsWidth + 220
    }

    private var stats: BandStats {
        computeStats(for: selectedBandId)
    }

    private var crossBandPills: some View {
        HStack(spacing: 4) {
            ForEach(BandEdges.hfBands) { band in
                let bandStats = computeStats(for: band.id)
                if bandStats.multCount > 0 {
                    crossBandChip(band: band, multCount: bandStats.multCount)
                }
            }
        }
        .fixedSize()
    }

    private func bandStatView(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .monospacedDigit()
                .fontWeight(count > 0 ? .medium : .regular)
                .foregroundStyle(count > 0 ? color : Color.secondary.opacity(0.5))
        }
    }

    private func crossBandChip(band: BandEdge, multCount: Int) -> some View {
        let isCurrentBand = band.id == selectedBandId
        return Text("\(band.label) \(multCount)")
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                isCurrentBand
                    ? Color(nsColor: .systemGreen).opacity(0.2)
                    : Color(nsColor: .systemGreen).opacity(0.1),
                in: Capsule()
            )
            .foregroundStyle(
                isCurrentBand
                    ? Color(nsColor: .systemGreen)
                    : .secondary
            )
    }

    private func computeStats(for bandId: String) -> BandStats {
        guard let band = BandEdges.hfBands.first(where: { $0.id == bandId }) else {
            return BandStats(totalCount: 0, newCount: 0, multCount: 0)
        }

        var total = 0
        var newCount = 0
        var multCount = 0

        for spot in spotAggregator.spots {
            guard spot.spot.frequencyKHz >= band.lowerKHz,
                  spot.spot.frequencyKHz <= band.upperKHz,
                  enabledSources.contains(spot.spot.source)
            else {
                continue
            }

            total += 1
            switch spot.neededStatus {
            case .newEntity:
                multCount += 1
                newCount += 1
            case .newBandSlot:
                multCount += 1
                newCount += 1
            case .unknown:
                newCount += 1
            case .workedNotConfirmed,
                 .confirmed:
                break
            }
        }

        return BandStats(totalCount: total, newCount: newCount, multCount: multCount)
    }
}

// MARK: - BandStats

private struct BandStats {
    let totalCount: Int
    let newCount: Int
    let multCount: Int
}
