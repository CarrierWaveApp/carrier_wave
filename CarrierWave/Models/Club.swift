import Foundation
import SwiftData

// MARK: - Club

@Model
nonisolated final class Club {
    // MARK: Lifecycle

    init(
        serverId: UUID,
        name: String,
        callsign: String? = nil,
        clubDescription: String? = nil
    ) {
        self.serverId = serverId
        self.name = name
        self.callsign = callsign
        self.clubDescription = clubDescription
        lastSyncedAt = Date()
    }

    // MARK: Internal

    var serverId = UUID()
    var name = ""
    var callsign: String?
    var clubDescription: String?
    var lastSyncedAt = Date()

    /// Non-optional wrapper for CloudKit-required optional relationship
    var members: [ClubMember] {
        get { membersRelation ?? [] }
        set { membersRelation = newValue }
    }

    var memberCount: Int {
        members.count
    }

    func isMember(callsign: String) -> Bool {
        members.contains { $0.callsign.uppercased() == callsign.uppercased() }
    }

    // MARK: Private

    @Relationship(deleteRule: .cascade, inverse: \ClubMember.club)
    private var membersRelation: [ClubMember]?
}

// MARK: - ClubMember

@Model
nonisolated final class ClubMember {
    // MARK: Lifecycle

    init(
        callsign: String,
        role: String = "member",
        club: Club? = nil
    ) {
        self.callsign = callsign
        self.role = role
        self.club = club
    }

    // MARK: Internal

    var callsign = ""
    var role = "member"
    var lastSeenAt: Date?
    var lastGrid: String?
    var club: Club?
}
