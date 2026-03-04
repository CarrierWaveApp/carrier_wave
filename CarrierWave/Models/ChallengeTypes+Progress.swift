import CarrierWaveData
import Foundation

// MARK: - ChallengeProgress

struct ChallengeProgress: Equatable, Sendable {
    // MARK: Lifecycle

    nonisolated init(
        completedGoals: [String] = [],
        currentValue: Int = 0,
        percentage: Double = 0,
        score: Int = 0,
        qualifyingQSOIds: [UUID] = [],
        lastUpdated: Date = Date()
    ) {
        self.completedGoals = completedGoals
        self.currentValue = currentValue
        self.percentage = percentage
        self.score = score
        self.qualifyingQSOIds = qualifyingQSOIds
        self.lastUpdated = lastUpdated
    }

    // MARK: Internal

    var completedGoals: [String]
    var currentValue: Int
    var percentage: Double
    var score: Int
    var qualifyingQSOIds: [UUID]
    var lastUpdated: Date
}

// MARK: Codable

extension ChallengeProgress: Codable {
    private enum CodingKeys: String, CodingKey {
        case completedGoals
        case currentValue
        case percentage
        case score
        case qualifyingQSOIds
        case lastUpdated
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedGoals = try container.decode([String].self, forKey: .completedGoals)
        currentValue = try container.decode(Int.self, forKey: .currentValue)
        percentage = try container.decode(Double.self, forKey: .percentage)
        score = try container.decode(Int.self, forKey: .score)
        qualifyingQSOIds = try container.decode([UUID].self, forKey: .qualifyingQSOIds)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(completedGoals, forKey: .completedGoals)
        try container.encode(currentValue, forKey: .currentValue)
        try container.encode(percentage, forKey: .percentage)
        try container.encode(score, forKey: .score)
        try container.encode(qualifyingQSOIds, forKey: .qualifyingQSOIds)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

// MARK: - LeaderboardEntry

struct LeaderboardEntry: Codable, Identifiable, Equatable, @unchecked Sendable {
    var rank: Int
    var callsign: String
    var score: Int
    var currentTier: String?
    var completedAt: Date?

    var id: String {
        callsign
    }
}

// MARK: - ChallengeConfiguration

/// Combined configuration stored as JSON in ChallengeDefinition
struct ChallengeConfiguration: Equatable, Sendable {
    var goals: [ChallengeGoal]
    var tiers: [ChallengeTier]?
    var criteria: QualificationCriteria
    var scoring: ScoringConfig
    var timeConstraints: TimeConstraints?
    var badges: [ChallengeBadge]?
    var historicalQSOsAllowed: Bool
    var inviteConfig: InviteConfig?
}

// MARK: Codable

extension ChallengeConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case goals
        case tiers
        case criteria
        case scoring
        case timeConstraints
        case badges
        case historicalQSOsAllowed
        case inviteConfig
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goals = try container.decode([ChallengeGoal].self, forKey: .goals)
        tiers = try container.decodeIfPresent([ChallengeTier].self, forKey: .tiers)
        criteria = try container.decode(QualificationCriteria.self, forKey: .criteria)
        scoring = try container.decode(ScoringConfig.self, forKey: .scoring)
        timeConstraints = try container.decodeIfPresent(
            TimeConstraints.self, forKey: .timeConstraints
        )
        badges = try container.decodeIfPresent([ChallengeBadge].self, forKey: .badges)
        historicalQSOsAllowed = try container.decode(Bool.self, forKey: .historicalQSOsAllowed)
        inviteConfig = try container.decodeIfPresent(InviteConfig.self, forKey: .inviteConfig)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(goals, forKey: .goals)
        try container.encodeIfPresent(tiers, forKey: .tiers)
        try container.encode(criteria, forKey: .criteria)
        try container.encode(scoring, forKey: .scoring)
        try container.encodeIfPresent(timeConstraints, forKey: .timeConstraints)
        try container.encodeIfPresent(badges, forKey: .badges)
        try container.encode(historicalQSOsAllowed, forKey: .historicalQSOsAllowed)
        try container.encodeIfPresent(inviteConfig, forKey: .inviteConfig)
    }
}

// MARK: - ServerProgress

struct ServerProgress: Codable, Equatable, @unchecked Sendable {
    var completedGoals: [String]
    var currentValue: Int
    var percentage: Double
    var score: Int
    var rank: Int?
    var currentTier: String?
}
