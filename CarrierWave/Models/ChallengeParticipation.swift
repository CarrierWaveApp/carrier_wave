import CarrierWaveData
import Foundation
import SwiftData

/// Nonisolated helper functions to work around @MainActor Codable conformance issues
nonisolated private func decodeProgress(from data: Data) -> ChallengeProgress? {
    try? JSONDecoder().decode(ChallengeProgress.self, from: data)
}

nonisolated private func encodeProgress(_ progress: ChallengeProgress) -> Data? {
    try? JSONEncoder().encode(progress)
}

// MARK: - ChallengeParticipation

@Model
nonisolated final class ChallengeParticipation {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        challengeDefinition: ChallengeDefinition,
        userId: String,
        joinedAt: Date = Date(),
        status: ParticipationStatus = .active,
        currentTier: String? = nil,
        completedAt: Date? = nil,
        progressData: Data? = nil,
        serverParticipationId: UUID? = nil
    ) {
        self.id = id
        self.challengeDefinition = challengeDefinition
        self.userId = userId
        self.joinedAt = joinedAt
        statusRawValue = status.rawValue
        self.currentTier = currentTier
        self.completedAt = completedAt
        self.progressData = progressData
        self.serverParticipationId = serverParticipationId
    }

    // MARK: Internal

    var id = UUID()
    var challengeDefinition: ChallengeDefinition?
    var userId = ""
    var joinedAt = Date()
    var statusRawValue = ParticipationStatus.active.rawValue

    var currentTier: String?
    var completedAt: Date?

    /// Progress stored as JSON
    var progressData: Data?

    /// Server-assigned participation ID for sync
    var serverParticipationId: UUID?

    /// Device-specific auth token for this participation (from join response)
    var deviceToken: String?

    /// Whether historical QSOs are allowed for this participation
    var historicalAllowed: Bool = false

    /// Current rank on server leaderboard
    var serverRank: Int?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    var status: ParticipationStatus {
        get { ParticipationStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    // MARK: - Progress Access

    var progress: ChallengeProgress {
        get {
            guard let data = progressData else {
                return ChallengeProgress()
            }
            return decodeProgress(from: data) ?? ChallengeProgress()
        }
        set {
            progressData = encodeProgress(newValue)
            needsSync = true
        }
    }

    // MARK: - Convenience

    /// Whether this participation is active
    var isActive: Bool {
        status == .active
    }

    /// Whether the challenge is complete
    var isComplete: Bool {
        status == .completed
    }

    /// Progress percentage (0-100)
    var progressPercentage: Double {
        progress.percentage
    }

    /// Number of completed goals
    var completedGoalsCount: Int {
        progress.completedGoals.count
    }

    /// Current score
    var score: Int {
        progress.score
    }

    /// Challenge name (convenience)
    var challengeName: String {
        challengeDefinition?.name ?? "Unknown Challenge"
    }

    /// Challenge type (convenience)
    var challengeType: ChallengeType? {
        challengeDefinition?.type
    }

    /// Total goals in challenge
    var totalGoals: Int {
        challengeDefinition?.totalGoals ?? 0
    }

    /// Remaining goals for collection challenges
    var remainingGoals: Int {
        totalGoals - completedGoalsCount
    }

    /// Progress display string
    var progressDisplayString: String {
        guard let definition = challengeDefinition else {
            return "—"
        }

        switch definition.type {
        case .collection:
            return "\(completedGoalsCount)/\(totalGoals)"
        case .cumulative:
            if let target = definition.targetValue {
                return "\(progress.currentValue)/\(target)"
            }
            return "\(progress.currentValue)"
        case .timeBounded:
            return "\(progress.currentValue)"
        }
    }

    /// Current tier display name
    var currentTierName: String? {
        guard let tierId = currentTier,
              let tiers = challengeDefinition?.tiers
        else {
            return nil
        }
        return tiers.first { $0.id == tierId }?.name
    }

    /// Next tier to achieve
    var nextTier: ChallengeTier? {
        guard let tiers = challengeDefinition?.sortedTiers else {
            return nil
        }

        let currentValue =
            challengeType == .collection
                ? completedGoalsCount
                : progress.currentValue

        return tiers.first { $0.threshold > currentValue }
    }

    /// Progress toward next tier (0-1)
    var tierProgress: Double {
        guard let next = nextTier else {
            return 1.0 // All tiers complete
        }

        let currentValue =
            challengeType == .collection
                ? completedGoalsCount
                : progress.currentValue

        let previousThreshold = previousTierThreshold(before: next)
        let range = next.threshold - previousThreshold
        guard range > 0 else {
            return 0
        }

        let progressInRange = currentValue - previousThreshold
        return Double(progressInRange) / Double(range)
    }

    // MARK: Private

    private func previousTierThreshold(before tier: ChallengeTier) -> Int {
        guard let tiers = challengeDefinition?.sortedTiers,
              let index = tiers.firstIndex(where: { $0.id == tier.id }), index > 0
        else {
            return 0
        }
        return tiers[index - 1].threshold
    }
}

// MARK: - Factory

extension ChallengeParticipation {
    /// Create a new participation when joining a challenge
    static func join(
        challenge: ChallengeDefinition,
        userId: String,
        serverParticipationId: UUID? = nil
    ) -> ChallengeParticipation {
        ChallengeParticipation(
            challengeDefinition: challenge,
            userId: userId,
            serverParticipationId: serverParticipationId
        )
    }
}
