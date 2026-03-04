import CarrierWaveData
import SwiftUI

// MARK: - Club Members Summary

extension SessionDetailView {
    /// Club members grouped by club name for display.
    var clubGroupedMembers: [(club: String, callsigns: [String])] {
        var callsignClubs: [(callsign: String, clubs: [String])] = []
        var seen = Set<String>()
        for qso in qsos {
            let key = qso.callsign.uppercased()
            guard seen.insert(key).inserted else {
                continue
            }
            let clubs = ClubsSyncService.shared.clubs(for: qso.callsign)
            guard !clubs.isEmpty else {
                continue
            }
            callsignClubs.append((callsign: qso.callsign, clubs: clubs))
        }

        // Invert: club -> [callsigns]
        var clubMap: [String: [String]] = [:]
        for entry in callsignClubs {
            for club in entry.clubs {
                clubMap[club, default: []].append(entry.callsign)
            }
        }

        return clubMap.sorted { $0.key < $1.key }
            .map { (club: $0.key, callsigns: $0.value) }
    }

    @ViewBuilder
    var clubMembersSummarySection: some View {
        let grouped = clubGroupedMembers
        if !grouped.isEmpty {
            let totalMembers = Set(grouped.flatMap(\.callsigns)).count
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        Text(
                            "Club Connections · "
                                + "\(totalMembers) member\(totalMembers == 1 ? "" : "s"), "
                                + "\(grouped.count) club\(grouped.count == 1 ? "" : "s")"
                        )
                        .font(.subheadline.weight(.medium))
                    }

                    ForEach(grouped, id: \.club) { entry in
                        clubCard(name: entry.club, callsigns: entry.callsigns)
                    }
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func clubCard(name: String, callsigns: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(callsigns, id: \.self) { call in
                    Text(call)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
