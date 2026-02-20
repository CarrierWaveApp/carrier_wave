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
        let clubDTOs = try await client.getMyClubs(sourceURL: sourceURL, authToken: authToken)

        // Update local models
        try updateLocalClubs(from: clubDTOs, sourceURL: sourceURL, authToken: authToken)
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

    private func updateLocalClubs(from dtos: [ClubDTO], sourceURL: String, authToken: String) throws {
        // Fetch existing local clubs
        let descriptor = FetchDescriptor<Club>()
        let existing = try modelContext.fetch(descriptor)
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        var seenIds = Set<UUID>()

        // Update/create clubs from server
        for dto in dtos {
            seenIds.insert(dto.id)

            if let local = existingById[dto.id] {
                // Update existing
                local.name = dto.name
                local.descriptionText = dto.description
            } else {
                // Create new
                let club = Club(
                    id: dto.id,
                    name: dto.name,
                    poloNotesListURL: "", // Will be populated by details sync
                    descriptionText: dto.description
                )
                modelContext.insert(club)
            }
        }

        // Remove clubs no longer on server
        for local in existing where !seenIds.contains(local.id) {
            modelContext.delete(local)
        }

        try modelContext.save()
    }

    private func updateClubFromDetails(_ details: ClubDetailDTO) throws {
        let detailsId = details.id
        let descriptor = FetchDescriptor<Club>(
            predicate: #Predicate { $0.id == detailsId }
        )

        let club: Club
        if let existing = try modelContext.fetch(descriptor).first {
            club = existing
        } else {
            club = Club(
                id: details.id,
                name: details.name,
                poloNotesListURL: details.poloNotesListURL ?? ""
            )
            modelContext.insert(club)
        }

        // Update fields
        club.name = details.name
        club.descriptionText = details.description
        club.poloNotesListURL = details.poloNotesListURL ?? ""
        club.lastSyncedAt = details.lastSyncedAt ?? Date()

        // Update member callsigns
        if let members = details.members {
            club.memberCallsigns = members.map(\.callsign)
        }

        try modelContext.save()
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
