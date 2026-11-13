import CarrierWaveData
import SwiftUI

// MARK: - ContestBandBreakdown

/// Compact per-band QSO / multiplier breakdown derived from the running score
/// snapshot. Shows only bands with activity, in the contest's band order.
struct ContestBandBreakdown: View {
    // MARK: Internal

    let score: ContestScoreSnapshot
    let bands: [String]

    var body: some View {
        if activeBands.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activeBands, id: \.self) { band in
                        bandCell(band)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: Private

    private var activeBands: [String] {
        bands.filter { (score.qsosByBand[$0] ?? 0) > 0 }
    }

    private func bandCell(_ band: String) -> some View {
        VStack(spacing: 1) {
            Text(band)
                .font(.caption2.weight(.semibold))
            Text("\(score.qsosByBand[band] ?? 0) Q")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("\(score.multsByBand[band] ?? 0) M")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.orange)
        }
        .frame(minWidth: 48)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }
}
