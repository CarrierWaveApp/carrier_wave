import MapKit
import SwiftData
import SwiftUI

// MARK: - ClubMapView

struct ClubMapView: View {
    // MARK: Internal

    let club: Club
    var memberStatuses: [String: MemberStatusDTO]

    var body: some View {
        if mappableMembers.isEmpty {
            ContentUnavailableView(
                "No Locations",
                systemImage: "map",
                description: Text(
                    "Member grid square locations will appear here"
                )
            )
        } else {
            Map {
                ForEach(
                    mappableMembers,
                    id: \.callsign
                ) { member in
                    if let coordinate = MaidenheadConverter.coordinate(
                        from: member.lastGrid ?? ""
                    ) {
                        Annotation(
                            member.callsign,
                            coordinate: coordinate
                        ) {
                            memberPin(for: member)
                        }
                    }
                }
            }
        }
    }

    // MARK: Private

    private var mappableMembers: [ClubMember] {
        club.members.filter { member in
            guard let grid = member.lastGrid else {
                return false
            }
            return MaidenheadConverter.coordinate(from: grid) != nil
        }
    }

    private func memberPin(
        for member: ClubMember
    ) -> some View {
        let status = memberStatuses[
            member.callsign.uppercased()
        ]
        return VStack(spacing: 2) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(pinColor(for: status))
            Text(member.callsign)
                .font(.caption2)
                .fontWeight(.medium)
        }
    }

    private func pinColor(
        for status: MemberStatusDTO?
    ) -> Color {
        switch status?.status {
        case .onAir: .green
        case .recentlyActive: .yellow
        case .inactive,
             .none: .blue
        }
    }
}

// MARK: - Preview

#Preview {
    ClubMapView(
        club: Club(
            serverId: UUID(),
            name: "Preview Club"
        ),
        memberStatuses: [:]
    )
    .modelContainer(
        for: [Club.self, ClubMember.self],
        inMemory: true
    )
}
