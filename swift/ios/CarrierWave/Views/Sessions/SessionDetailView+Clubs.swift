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
            let topClubs = grouped.sorted { $0.callsigns.count > $1.callsigns.count }
            let preview = topClubs.prefix(3)
                .map { "\($0.club) (\($0.callsigns.count))" }
                .joined(separator: ", ")

            Section("Club Connections") {
                DisclosureGroup {
                    ForEach(grouped, id: \.club) { entry in
                        ClubCardView(
                            name: entry.club,
                            callsigns: entry.callsigns
                        )
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(.blue)
                            Text(
                                "\(totalMembers) member\(totalMembers == 1 ? "" : "s") · "
                                    + "\(grouped.count) club\(grouped.count == 1 ? "" : "s")"
                            )
                            .fontWeight(.medium)
                        }
                        .font(.subheadline)

                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - ClubCardView

private struct ClubCardView: View {
    // MARK: Internal

    let name: String
    let callsigns: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(callsigns, id: \.self) { call in
                    Text(call)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, capsuleVerticalPadding)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: Private

    @ScaledMetric(relativeTo: .caption) private var capsuleVerticalPadding: CGFloat = 4
}
