import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ClubStatsView

struct ClubStatsView: View {
    // MARK: Internal

    let club: FfiClub
    let memberStatuses: [String: FfiMemberStatus]

    var body: some View {
        Section("Stats") {
            LabeledContent(
                "Members",
                value: "\(Int(club.cachedMemberCount))"
            )
            LabeledContent(
                "On Air",
                value: "\(onAirCount)"
            )
            LabeledContent(
                "Recently Active",
                value: "\(recentlyActiveCount)"
            )
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
}

// MARK: - Preview

#Preview {
    List {
        ClubStatsView(
            club: FfiClub(
                id: "preview",
                name: "Preview Club",
                callsign: nil,
                description: nil,
                notesUrl: nil,
                notesTitle: nil,
                hasLogo: false,
                cachedMemberCount: 0,
                lastSyncedAt: 0
            ),
            memberStatuses: [:]
        )
    }
}
