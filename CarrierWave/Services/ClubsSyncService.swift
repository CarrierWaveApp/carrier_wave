import Combine
import Foundation
import SwiftData

// MARK: - ClubsSyncService

@MainActor
final class ClubsSyncService: ObservableObject {
    // MARK: Lifecycle

    init(modelContext: ModelContext, client: ActivitiesClient? = nil) {
        self.modelContext = modelContext
        self.client = client ?? ActivitiesClient()
    }

    // MARK: Internal

    @Published var isSyncing = false
    @Published var syncError: String?

    let modelContext: ModelContext
    let client: ActivitiesClient

    // MARK: - Sync

    /// Sync clubs from server
    func syncClubs(sourceURL: String) async throws {
        guard let authToken = await client.ensureAuthToken() else {
            throw ClubsSyncError.notAuthenticated
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        // Fetch clubs from server
        let clubDTOs = try await client.getMyClubs(
            sourceURL: sourceURL,
            authToken: authToken
        )

        // Update local models
        try updateLocalClubs(from: clubDTOs)
    }

    /// Sync a specific club's details and members
    func syncClubDetails(clubId: UUID, sourceURL: String) async throws {
        guard let authToken = await client.ensureAuthToken() else {
            throw ClubsSyncError.notAuthenticated
        }

        let details = try await client.getClubDetails(
            clubId: clubId,
            sourceURL: sourceURL,
            authToken: authToken,
            includeMembers: true
        )

        try updateClubFromDetails(details)
    }

    // MARK: Private

    private func updateLocalClubs(from dtos: [ClubDTO]) throws {
        // Fetch existing local clubs
        let descriptor = FetchDescriptor<Club>()
        let existing = try modelContext.fetch(descriptor)
        let existingById = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.serverId, $0) }
        )

        var seenIds = Set<UUID>()

        // Update/create clubs from server
        for dto in dtos {
            seenIds.insert(dto.id)

            if let local = existingById[dto.id] {
                // Update existing
                local.name = dto.name
                local.callsign = dto.callsign
                local.clubDescription = dto.description
            } else {
                // Create new
                let club = Club(
                    serverId: dto.id,
                    name: dto.name,
                    callsign: dto.callsign,
                    clubDescription: dto.description
                )
                modelContext.insert(club)
            }
        }

        // Remove clubs no longer on server
        for local in existing where !seenIds.contains(local.serverId) {
            modelContext.delete(local)
        }

        try modelContext.save()
    }

    private func updateClubFromDetails(_ details: ClubDetailDTO) throws {
        let detailsId = details.id
        let descriptor = FetchDescriptor<Club>(
            predicate: #Predicate { $0.serverId == detailsId }
        )

        let club: Club
        if let existing = try modelContext.fetch(descriptor).first {
            club = existing
        } else {
            club = Club(
                serverId: details.id,
                name: details.name,
                callsign: details.callsign,
                clubDescription: details.description
            )
            modelContext.insert(club)
        }

        // Update fields
        club.name = details.name
        club.callsign = details.callsign
        club.clubDescription = details.description
        club.lastSyncedAt = Date()

        // Update members from DTOs
        if let memberDTOs = details.members {
            try updateMembers(for: club, from: memberDTOs)
        }

        try modelContext.save()
    }

    private func updateMembers(
        for club: Club,
        from dtos: [ClubMemberDTO]
    ) throws {
        let existingMembers = club.members
        let existingByCallsign = Dictionary(
            uniqueKeysWithValues: existingMembers.map {
                ($0.callsign.uppercased(), $0)
            }
        )

        var seenCallsigns = Set<String>()

        for dto in dtos {
            let key = dto.callsign.uppercased()
            seenCallsigns.insert(key)

            if let existing = existingByCallsign[key] {
                // Update existing member
                existing.role = dto.role
                existing.lastSeenAt = dto.lastSeenAt
                existing.lastGrid = dto.lastGrid
            } else {
                // Create new member
                let member = ClubMember(
                    callsign: dto.callsign,
                    role: dto.role,
                    club: club
                )
                member.lastSeenAt = dto.lastSeenAt
                member.lastGrid = dto.lastGrid
                modelContext.insert(member)
            }
        }

        // Remove members no longer in the club
        for member in existingMembers
            where !seenCallsigns.contains(member.callsign.uppercased())
        {
            modelContext.delete(member)
        }
    }
}

// MARK: - ClubsSyncError

enum ClubsSyncError: LocalizedError {
    case notAuthenticated
    case syncFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Please sign in to view clubs"
        case let .syncFailed(message):
            "Sync failed: \(message)"
        }
    }
}
