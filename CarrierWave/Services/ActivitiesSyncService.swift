import Combine
import Foundation
import SwiftData
import UIKit

@MainActor
final class ActivitiesSyncService: ObservableObject {
    // MARK: Lifecycle

    init(modelContext: ModelContext, client: ActivitiesClient? = nil) {
        self.modelContext = modelContext
        self.client = client ?? ActivitiesClient()
        progressEngine = ChallengeProgressEngine(modelContext: modelContext)
    }

    // MARK: Internal

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    let modelContext: ModelContext
    let client: ActivitiesClient
    let progressEngine: ChallengeProgressEngine

    /// Default polling interval for leaderboards (30 seconds)
    let leaderboardPollingInterval: TimeInterval = 30

    /// Check if challenges sync is enabled
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "activitiesSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "activitiesSyncEnabled") }
    }

    // MARK: - Source Management

    /// Fetch the official challenge source (creates if needed)
    func getOrCreateOfficialSource() throws -> ChallengeSource {
        let officialRaw = ChallengeSourceType.official.rawValue
        let descriptor = FetchDescriptor<ChallengeSource>(
            predicate: #Predicate { $0.typeRawValue == officialRaw }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            var needsSave = false
            // Update URL if it changed (e.g., migrated from placeholder)
            if existing.url != "https://activities.carrierwave.app" {
                existing.url = "https://activities.carrierwave.app"
                existing.lastError = nil
                needsSave = true
            }
            // Clear stale errors from old URL
            if existing.lastError != nil, existing.url == "https://activities.carrierwave.app" {
                existing.lastError = nil
                needsSave = true
            }
            if needsSave {
                try modelContext.save()
            }
            return existing
        }

        let official = ChallengeSource(
            type: .official,
            url: "https://activities.carrierwave.app",
            name: "Carrier Wave Official"
        )
        modelContext.insert(official)
        try modelContext.save()
        return official
    }

    /// Add a community source
    func addCommunitySource(url: String, name: String) throws -> ChallengeSource {
        let source = ChallengeSource(
            type: .community,
            url: url,
            name: name
        )
        modelContext.insert(source)
        try modelContext.save()
        return source
    }

    /// Remove a source (and its challenges)
    func removeSource(_ source: ChallengeSource) throws {
        modelContext.delete(source)
        try modelContext.save()
    }

    /// Fetch all enabled sources
    func fetchEnabledSources() throws -> [ChallengeSource] {
        let descriptor = FetchDescriptor<ChallengeSource>(
            predicate: #Predicate { $0.isEnabled }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Challenge Fetching

    /// Refresh challenges from all enabled sources
    /// - Parameter forceUpdate: If true, updates all challenges regardless of version
    func refreshChallenges(forceUpdate: Bool = false) async throws {
        isSyncing = true
        syncError = nil

        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        // Auto-register if opted in but missing auth token
        await ensureRegisteredIfEnabled()

        // Clean up any duplicate challenge definitions first
        try deduplicateChallengeDefinitions()

        let sources = try fetchEnabledSources()

        for source in sources {
            do {
                try await refreshChallenges(from: source, forceUpdate: forceUpdate)
            } catch {
                source.lastError = error.localizedDescription
                syncError = "Failed to refresh \(source.name): \(error.localizedDescription)"
            }
        }

        // Save before fetching participating challenges so the fetch can see newly inserted definitions
        try modelContext.save()

        // Also refresh participating challenges for the user's callsign
        do {
            try await refreshParticipatingChallenges(forceUpdate: forceUpdate)
        } catch {
            // Log but don't fail the whole refresh
            print("[ActivitiesSyncService] Failed to refresh participating challenges: \(error)")
        }

        try modelContext.save()
    }

    /// Refresh challenges that the user is participating in from the server
    /// - Parameter forceUpdate: If true, updates all challenges regardless of version
    func refreshParticipatingChallenges(forceUpdate: Bool = false) async throws {
        let callsign = UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        guard !callsign.isEmpty else {
            return
        }

        // Use global auth token first, fall back to participation tokens
        guard let authToken = resolveAuthToken() else {
            // No auth token available
            return
        }

        let sources = try fetchEnabledSources()

        for source in sources {
            print(
                "[ActivitiesSyncService] curl '\(source.url)/v1/participants/\(callsign)/challenges'"
            )

            do {
                let participatingChallenges = try await client.fetchParticipatingChallenges(
                    callsign: callsign,
                    sourceURL: source.url,
                    authToken: authToken
                )

                // For each participating challenge, ensure we have the full definition
                for participation in participatingChallenges {
                    // Check if we already have this challenge definition
                    let challengeId = participation.challengeId
                    let descriptor = FetchDescriptor<ChallengeDefinition>(
                        predicate: #Predicate { $0.id == challengeId }
                    )

                    if try modelContext.fetch(descriptor).first == nil {
                        // Fetch the full challenge definition
                        print(
                            "[ActivitiesSyncService] curl '\(source.url)/v1/challenges/\(challengeId)'"
                        )
                        let dto = try await client.fetchChallenge(
                            id: challengeId,
                            from: source.url
                        )
                        let definition = try ChallengeDefinition.from(dto: dto, source: source)
                        modelContext.insert(definition)
                    }
                }
            } catch {
                print(
                    "[ActivitiesSyncService] Failed to fetch participating challenges from \(source.name): \(error)"
                )
            }
        }
    }

    /// Refresh challenges from a specific source
    /// - Parameter forceUpdate: If true, updates all challenges regardless of version
    func refreshChallenges(from source: ChallengeSource, forceUpdate: Bool = false) async throws {
        print("[ActivitiesSyncService] curl '\(source.url)/v1/challenges?active=true'")

        let listData = try await client.fetchChallenges(from: source.url, active: true)

        // Fetch full details for each challenge in the list
        for listItem in listData.challenges {
            print("[ActivitiesSyncService] curl '\(source.url)/v1/challenges/\(listItem.id)'")

            let dto = try await client.fetchChallenge(id: listItem.id, from: source.url)

            // Check if challenge already exists (globally, not just for this source)
            let challengeId = dto.id
            let descriptor = FetchDescriptor<ChallengeDefinition>(
                predicate: #Predicate { $0.id == challengeId }
            )

            if let existing = try modelContext.fetch(descriptor).first {
                // Update existing if version changed or force update requested
                if forceUpdate || dto.version > existing.version {
                    try existing.update(from: dto)
                    // Re-evaluate progress for all participations
                    for participation in existing.participations {
                        progressEngine.reevaluateAllQSOs(for: participation)
                    }
                }
            } else {
                // Create new
                let definition = try ChallengeDefinition.from(dto: dto, source: source)
                modelContext.insert(definition)
            }
        }

        source.lastFetched = Date()
        source.lastError = nil
    }

    // MARK: Private

    /// If user opted in to community features but has no auth token, register now.
    /// After successful registration, updates any stale participation tokens.
    private func ensureRegisteredIfEnabled() async {
        let enabled = UserDefaults.standard.bool(forKey: "activitiesServerEnabled")
        guard enabled, !client.hasAuthToken() else {
            return
        }

        let callsign = UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        guard !callsign.isEmpty else {
            return
        }

        do {
            _ = try await client.register(
                callsign: callsign.uppercased(),
                deviceName: UIDevice.current.name,
                sourceURL: "https://activities.carrierwave.app"
            )
            // After re-registration, update stale participation tokens
            try updateParticipationTokens()
        } catch {
            print("[ActivitiesSyncService] Auto-registration failed: \(error)")
        }
    }

    /// Resolve the best available auth token: global keychain token first,
    /// then fall back to a participation-stored token.
    func resolveAuthToken() -> String? {
        if let global = try? client.getAuthToken() {
            return global
        }
        // Fall back to any participation token as last resort
        let activeRaw = ParticipationStatus.active.rawValue
        var descriptor = FetchDescriptor<ChallengeParticipation>(
            predicate: #Predicate { $0.statusRawValue == activeRaw },
            sortBy: [SortDescriptor(\.joinedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.deviceToken
    }

    /// Update all participation device tokens to match the current global auth token.
    /// Called after re-registration to recover from stale per-participation tokens.
    private func updateParticipationTokens() throws {
        guard let globalToken = try? client.getAuthToken() else {
            return
        }

        let activeRaw = ParticipationStatus.active.rawValue
        let descriptor = FetchDescriptor<ChallengeParticipation>(
            predicate: #Predicate { $0.statusRawValue == activeRaw }
        )
        let participations = try modelContext.fetch(descriptor)

        var updatedCount = 0
        for participation in participations where participation.deviceToken != globalToken {
            participation.deviceToken = globalToken
            updatedCount += 1
        }

        if updatedCount > 0 {
            print(
                "[ActivitiesSyncService] Updated \(updatedCount) stale participation tokens"
            )
            try modelContext.save()
        }
    }

    /// Remove duplicate ChallengeDefinition records, merging participations to the surviving record
    private func deduplicateChallengeDefinitions() throws {
        let descriptor = FetchDescriptor<ChallengeDefinition>()
        let allDefinitions = try modelContext.fetch(descriptor)

        // Group by challenge ID
        var definitionsById: [UUID: [ChallengeDefinition]] = [:]
        for definition in allDefinitions {
            definitionsById[definition.id, default: []].append(definition)
        }

        // For each group with duplicates, keep the first and merge participations
        for (challengeId, definitions) in definitionsById where definitions.count > 1 {
            print(
                "[ActivitiesSyncService] Found \(definitions.count) duplicates for challenge \(challengeId)"
            )

            let keeper = definitions[0]
            let duplicates = definitions.dropFirst()

            for duplicate in duplicates {
                // Move participations to the keeper
                for participation in duplicate.participations {
                    participation.challengeDefinition = keeper
                }
                // Delete the duplicate
                modelContext.delete(duplicate)
            }
        }

        // Also deduplicate participations (same user + same challenge)
        try deduplicateParticipations()
    }

    /// Remove duplicate ChallengeParticipation records for the same user and challenge
    private func deduplicateParticipations() throws {
        let descriptor = FetchDescriptor<ChallengeParticipation>()
        let allParticipations = try modelContext.fetch(descriptor)

        // Group by (userId, challengeDefinition.id)
        var participationsByKey: [String: [ChallengeParticipation]] = [:]
        for participation in allParticipations {
            guard let challengeId = participation.challengeDefinition?.id else {
                continue
            }
            let key = "\(participation.userId)-\(challengeId)"
            participationsByKey[key, default: []].append(participation)
        }

        // For each group with duplicates, keep the one with most progress
        for (key, participations) in participationsByKey where participations.count > 1 {
            print(
                "[ActivitiesSyncService] Found \(participations.count) duplicate participations for \(key)"
            )

            // Sort by progress (descending) to keep the one with most progress
            let sorted = participations.sorted {
                $0.progress.completedGoals.count > $1.progress.completedGoals.count
            }

            let keeper = sorted[0]
            let duplicates = sorted.dropFirst()

            for duplicate in duplicates {
                modelContext.delete(duplicate)
            }

            print(
                "[ActivitiesSyncService] Kept participation with \(keeper.progress.completedGoals.count) goals"
            )
        }
    }
}
