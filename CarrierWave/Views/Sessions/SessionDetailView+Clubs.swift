import CarrierWaveData
import SwiftUI

// MARK: - Club Members Summary

extension SessionDetailView {
    /// Club members contacted during this session
    var clubMemberQSOs: [(callsign: String, clubs: [String])] {
        var seen = Set<String>()
        var results: [(callsign: String, clubs: [String])] = []
        for qso in qsos {
            let key = qso.callsign.uppercased()
            guard !seen.contains(key) else {
                continue
            }
            let clubs = ClubsSyncService.shared.clubs(for: qso.callsign)
            guard !clubs.isEmpty else {
                continue
            }
            seen.insert(key)
            results.append((callsign: qso.callsign, clubs: clubs))
        }
        return results
    }

    @ViewBuilder
    var clubMembersSummarySection: some View {
        let members = clubMemberQSOs
        if !members.isEmpty {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            "You worked \(members.count) club member"
                                + "\(members.count == 1 ? "" : "s")"
                        )
                        .font(.subheadline.weight(.medium))
                        Text(members.map(\.callsign).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                ForEach(members, id: \.callsign) { member in
                    HStack {
                        Text(member.callsign)
                            .font(
                                .subheadline.weight(.medium).monospaced()
                            )
                        Spacer()
                        Text(member.clubs.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
