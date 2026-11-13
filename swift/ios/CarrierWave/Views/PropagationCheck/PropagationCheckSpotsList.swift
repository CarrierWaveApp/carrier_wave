import CarrierWaveData
import SwiftUI

// MARK: - PropagationCheckSpotsList

/// Section listing every captured spot, newest first. Shows skimmer callsign,
/// band, source (RBN/PSKR), timestamp, SNR, and distance from operator.
struct PropagationCheckSpotsList: View {
    let enrichedSpots: [PropagationEnrichedSpot]

    var body: some View {
        let sorted = enrichedSpots.sorted { $0.entry.timestamp > $1.entry.timestamp }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spots")
                    .font(.headline)
                Spacer()
                Text("\(sorted.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if sorted.isEmpty {
                Text("No spots captured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(sorted) { spot in
                        SpotRow(spot: spot)
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - SpotRow

private struct SpotRow: View {
    // MARK: Internal

    let spot: PropagationEnrichedSpot

    var body: some View {
        let band = spot.entry.band ?? ""
        HStack(spacing: 10) {
            Circle()
                .fill(BandColors.color(for: band))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spot.entry.skimmerCall)
                        .font(.body.monospaced())
                    if !band.isEmpty {
                        Text(band)
                            .font(.caption2.bold())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(BandColors.color(for: band).opacity(0.18), in: Capsule())
                            .foregroundStyle(BandColors.color(for: band))
                    }
                    Text(spot.entry.source.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(spot.entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let snr = spot.entry.snrDB {
                    Text("\(Int(snr)) dB")
                        .font(.subheadline.monospacedDigit())
                } else {
                    Text("—")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(distanceLabel(spot.distanceKm))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Private

    private func distanceLabel(_ kilometers: Double?) -> String {
        guard let kilometers, kilometers > 0 else {
            return "—"
        }
        return "\(Int(kilometers * 0.621371)) mi"
    }
}
