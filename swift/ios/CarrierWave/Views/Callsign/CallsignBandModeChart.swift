import CarrierWaveData
import SwiftUI

// MARK: - CallsignBandModeChart

/// Horizontal bar chart showing QSO distribution across bands with mode breakdown.
struct CallsignBandModeChart: View {
    // MARK: Internal

    let qsos: [QSO]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Band / Mode")
                .font(.headline)

            ForEach(bandData, id: \.band) { entry in
                bandRow(entry: entry)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private var maxCount: Int {
        bandData.first?.count ?? 1
    }

    private var bandData: [BandEntry] {
        var grouped: [String: [String: Int]] = [:]
        for qso in qsos {
            grouped[qso.band, default: [:]][qso.mode, default: 0] += 1
        }
        return grouped.map { band, modes in
            let total = modes.values.reduce(0, +)
            let modeBreakdown = modes.sorted { $0.value > $1.value }
                .map { ModeCount(mode: $0.key, count: $0.value) }
            return BandEntry(band: band, count: total, modes: modeBreakdown)
        }
        .sorted { $0.count > $1.count }
    }

    private func bandRow(entry: BandEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.band)
                .font(.caption.weight(.semibold).monospaced())
                .frame(width: 36, alignment: .trailing)

            GeometryReader { geo in
                let fraction = Double(entry.count) / Double(max(maxCount, 1))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: 20)

            Text("\(entry.count)")
                .font(.caption.weight(.semibold))
                .frame(width: 24, alignment: .trailing)

            modeBadges(entry.modes)
        }
    }

    private func modeBadges(_ modes: [ModeCount]) -> some View {
        HStack(spacing: 4) {
            ForEach(modes.prefix(3), id: \.mode) { mc in
                Text("\(mc.mode)(\(mc.count))")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .fixedSize()
    }
}

// MARK: - BandEntry

private struct BandEntry {
    let band: String
    let count: Int
    let modes: [ModeCount]
}

// MARK: - ModeCount

private struct ModeCount {
    let mode: String
    let count: Int
}
