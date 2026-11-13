import SwiftUI

// MARK: - BandScopeCrossBandHints

/// Strip of "Matches: 80m (3) · 40m (12) · …" chips that appears
/// above any band scope when the SQL filter is active. Without this,
/// queries that match spots only on bands other than the selected
/// one render as a blank canvas — the user can't tell whether the
/// query is broken or just picked a different band.
///
/// Tap any chip to switch the visible band. Hides itself when there
/// are zero matches anywhere — no point showing an empty strip.
struct BandScopeCrossBandHints: View {
    // MARK: Internal

    @Binding var selectedBandId: String

    let allowedSpotIDs: Set<String>?
    let spots: [EnrichedSpot]

    var body: some View {
        let counts = bandCounts.filter { $0.matchCount > 0 }
        if !counts.isEmpty {
            HStack(spacing: 4) {
                Text("Matches:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(counts, id: \.bandId) { entry in
                    chip(entry: entry)
                }
                Spacer()
                Text("\(counts.map(\.matchCount).reduce(0, +)) total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.05))
        }
    }

    // MARK: Private

    private struct Entry {
        let bandId: String
        let label: String
        let matchCount: Int
    }

    private var bandCounts: [Entry] {
        guard let allowedSpotIDs else {
            return []
        }
        let allowed = spots.filter { allowedSpotIDs.contains($0.spot.id) }
        return BandEdges.hfBands.map { band in
            let count = allowed.lazy
                .filter {
                    $0.spot.frequencyKHz >= band.lowerKHz
                        && $0.spot.frequencyKHz <= band.upperKHz
                }
                .count
            return Entry(bandId: band.id, label: band.label, matchCount: count)
        }
    }

    private func chip(entry: Entry) -> some View {
        let isSelected = entry.bandId == selectedBandId
        return Button {
            selectedBandId = entry.bandId
        } label: {
            HStack(spacing: 3) {
                Text(entry.label)
                    .font(.caption2)
                    .fontWeight(isSelected ? .bold : .regular)
                Text("\(entry.matchCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.25)
                    : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.borderless)
    }
}
