import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ClubStatsView

struct ClubStatsView: View {
    // MARK: Internal

    let club: Club
    let memberStatuses: [String: MemberStatusDTO]

    var body: some View {
        Section("Stats") {
            LabeledContent(
                "Members",
                value: "\(club.memberCount)"
            )
            LabeledContent(
                "On Air",
                value: "\(onAirCount)"
            )
            LabeledContent(
                "Recently Active",
                value: "\(recentlyActiveCount)"
            )
            if !gridsRepresented.isEmpty {
                LabeledContent(
                    "Grid Squares",
                    value: "\(gridsRepresented.count)"
                )
            }
        }
    }

    // MARK: Private

    private var onAirCount: Int {
        memberStatuses.values
            .filter { $0.status == .onAir }
            .count
    }

    private var recentlyActiveCount: Int {
        memberStatuses.values
            .filter { $0.status == .recentlyActive }
            .count
    }

    private var gridsRepresented: Set<String> {
        Set(club.members.compactMap(\.lastGrid))
    }
}

// MARK: - Preview

#Preview {
    List {
        ClubStatsView(
            club: Club(
                serverId: UUID(),
                name: "Preview Club"
            ),
            memberStatuses: [:]
        )
    }
    .modelContainer(
        for: [Club.self, ClubMember.self],
        inMemory: true
    )
}
