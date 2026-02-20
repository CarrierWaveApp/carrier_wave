import Foundation
import SwiftData

// MARK: - LeaderboardCache

@Model
nonisolated final class LeaderboardCache {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        challengeId: UUID,
        entriesData: Data = Data(),
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.challengeId = challengeId
        self.entriesData = entriesData
        self.lastUpdated = lastUpdated
    }

    // MARK: Internal

    var id = UUID()
    var challengeId = UUID()
    var entriesData = Data()
    var lastUpdated = Date()

    // MARK: - Entries Access

    var entries: [LeaderboardEntry] {
        get {
            (try? JSONDecoder().decode([LeaderboardEntry].self, from: entriesData)) ?? []
        }
        set {
            entriesData = (try? JSONEncoder().encode(newValue)) ?? Data()
            lastUpdated = Date()
        }
    }

    /// Number of participants
    var participantCount: Int {
        entries.count
    }

    /// Top N entries
    func topEntries(_ count: Int) -> [LeaderboardEntry] {
        Array(entries.prefix(count))
    }

    /// Find current user's entry
    func currentUserEntry(callsign: String) -> LeaderboardEntry? {
        entries.first { $0.callsign.uppercased() == callsign.uppercased() }
    }

    /// Current user's rank
    func currentUserRank(callsign: String) -> Int? {
        currentUserEntry(callsign: callsign)?.rank
    }

    /// Whether the cache is stale (older than specified interval)
    func isStale(olderThan interval: TimeInterval = 30) -> Bool {
        Date().timeIntervalSince(lastUpdated) > interval
    }
}

// MARK: - Factory

extension LeaderboardCache {
    /// Create from API response
    static func from(challengeId: UUID, data: LeaderboardData) -> LeaderboardCache {
        let cache = LeaderboardCache(challengeId: challengeId)
        cache.entries = data.leaderboard
        cache.lastUpdated = data.lastUpdated
        return cache
    }

    /// Update from API response
    func update(from data: LeaderboardData) {
        entries = data.leaderboard
        lastUpdated = data.lastUpdated
    }
}
