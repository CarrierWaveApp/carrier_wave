import CarrierWaveData
import Combine
import Foundation
import SwiftData

// MARK: - ClubsSyncService

@MainActor
final class ClubsSyncService: ObservableObject {
    // MARK: Lifecycle

    /// Create a view-scoped instance (for testing or standalone use).
    init(modelContext: ModelContext, client: ActivitiesClient? = nil) {
        self.modelContext = modelContext
        self.client = client ?? ActivitiesClient()
        rebuildCallsignCache()
    }

    /// Private init for the shared singleton (no ModelContext yet).
    private init() {}

    // MARK: Internal

    /// Shared singleton — call `configure(container:)` from app entry point.
    static let shared = ClubsSyncService()

    @Published var isSyncing = false
    @Published var syncError: String?

    /// In-memory set of all club member callsigns for O(1) lookup
    @Published private(set) var clubMemberCallsigns: Set<String> = []

    /// Map of callsign -> [club name] for display in logger/QSO detail
    @Published private(set) var clubsByCallsign: [String: [String]] = [:]

    /// Configure the shared instance with a model container.
    /// Call from the app entry point after ModelContainer is ready.
    func configure(container: ModelContainer) {
        modelContext = container.mainContext
        client = ActivitiesClient()
        rebuildCallsignCache()
    }

    // MARK: - Cache

    /// Rebuild in-memory lookups from SwiftData, cleaning up duplicates
    func rebuildCallsignCache() {
        guard let ctx = modelContext else {
            return
        }
        let descriptor = FetchDescriptor<ClubMember>()
        guard let members = try? ctx.fetch(descriptor) else {
            return
        }

        // Deduplicate: keep one member per (callsign, club) pair
        var seen: [String: ClubMember] = [:]
        var duplicateCount = 0
        for member in members {
            let clubId = member.club?.serverId.uuidString ?? "orphan"
            let key = "\(member.callsign.uppercased())_\(clubId)"
            if seen[key] != nil {
                ctx.delete(member)
                duplicateCount += 1
            } else {
                seen[key] = member
            }
        }
        if duplicateCount > 0 {
            try? ctx.save()
        }

        var callsigns = Set<String>()
        var byCallsign: [String: Set<String>] = [:]

        for (_, member) in seen {
            let callKey = member.callsign.uppercased()
            callsigns.insert(callKey)
            if let clubName = member.club?.name {
                byCallsign[callKey, default: []].insert(clubName)
            }
        }

        clubMemberCallsigns = callsigns
        clubsByCallsign = byCallsign.mapValues { Array($0) }
    }

    /// Check if a callsign is a club member, returns matching club names
    func clubs(for callsign: String) -> [String] {
        clubsByCallsign[callsign.uppercased()] ?? []
    }

    // MARK: - Sync

    /// Sync clubs from server, fetching all clubs and their members
    func syncClubs(sourceURL: String) async throws {
        guard let ctx = modelContext else {
            return
        }
        guard let authToken = await resolvedClient.ensureAuthToken() else {
            throw ClubsSyncError.notAuthenticated
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        // Fetch clubs from server
        let clubDTOs = try await resolvedClient.getMyClubs(
            sourceURL: sourceURL,
            authToken: authToken
        )

        // Update local models
        try updateLocalClubs(from: clubDTOs, context: ctx)
    }

    /// Sync a specific club's details and members
    func syncClubDetails(clubId: UUID, sourceURL: String) async throws {
        guard let ctx = modelContext else {
            return
        }
        guard let authToken = await resolvedClient.ensureAuthToken() else {
            throw ClubsSyncError.notAuthenticated
        }

        let details = try await resolvedClient.getClubDetails(
            clubId: clubId,
            sourceURL: sourceURL,
            authToken: authToken,
            includeMembers: true
        )

        try updateClubFromDetails(details, context: ctx)
    }

    // MARK: Private

    private var modelContext: ModelContext?
    private var client: ActivitiesClient?

    /// Resolved client, creating a default if none was provided.
    private var resolvedClient: ActivitiesClient {
        if let client {
            return client
        }
        let newClient = ActivitiesClient()
        client = newClient
        return newClient
    }

    private func updateLocalClubs(
        from dtos: [ClubDTO],
        context: ModelContext
    ) throws {
        // Fetch existing local clubs
        let descriptor = FetchDescriptor<Club>()
        let existing = try context.fetch(descriptor)
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
                local.notesURL = dto.notesUrl
                local.notesTitle = dto.notesTitle
            } else {
                // Create new
                let club = Club(
                    serverId: dto.id,
                    name: dto.name,
                    callsign: dto.callsign,
                    clubDescription: dto.description,
                    notesURL: dto.notesUrl,
                    notesTitle: dto.notesTitle
                )
                context.insert(club)
            }
        }

        // Remove clubs no longer on server
        for local in existing where !seenIds.contains(local.serverId) {
            context.delete(local)
        }

        try context.save()
        rebuildCallsignCache()
    }

    private func updateClubFromDetails(
        _ details: ClubDetailDTO,
        context: ModelContext
    ) throws {
        let detailsId = details.id
        let descriptor = FetchDescriptor<Club>(
            predicate: #Predicate { $0.serverId == detailsId }
        )

        let club: Club
        if let existing = try context.fetch(descriptor).first {
            club = existing
        } else {
            club = Club(
                serverId: details.id,
                name: details.name,
                callsign: details.callsign,
                clubDescription: details.description,
                notesURL: details.notesUrl,
                notesTitle: details.notesTitle
            )
            context.insert(club)
        }

        // Update fields
        club.name = details.name
        club.callsign = details.callsign
        club.clubDescription = details.description
        club.notesURL = details.notesUrl
        club.notesTitle = details.notesTitle
        club.lastSyncedAt = Date()

        // Update members from DTOs
        if let memberDTOs = details.members {
            try updateMembers(for: club, from: memberDTOs, context: context)
        }

        try context.save()
        rebuildCallsignCache()
    }

    private func updateMembers(
        for club: Club,
        from dtos: [ClubMemberDTO],
        context: ModelContext
    ) throws {
        // Fetch members via descriptor instead of the optional relationship,
        // which can fail to fault in persisted members and cause duplicates.
        let allMembers = try context.fetch(FetchDescriptor<ClubMember>())
        let clubId = club.serverId
        let existingMembers = allMembers.filter {
            $0.club?.serverId == clubId
        }
        let existingByCallsign = Dictionary(
            existingMembers.map { ($0.callsign.uppercased(), $0) },
            uniquingKeysWith: { first, duplicate in
                // Clean up any pre-existing duplicates
                context.delete(duplicate)
                return first
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
                context.insert(member)
            }
        }

        // Remove members no longer in the club
        for member in existingMembers
            where !seenCallsigns.contains(member.callsign.uppercased())
        {
            context.delete(member)
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
