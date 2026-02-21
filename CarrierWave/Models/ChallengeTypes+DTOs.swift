import Foundation

// MARK: - RegisterRequestBody

struct RegisterRequestBody: Codable {
    var callsign: String
    var deviceName: String?
}

// MARK: - RegisterResponseDTO

struct RegisterResponseDTO: Codable {
    var userId: String
    var deviceToken: String
}

// MARK: - APIResponse

struct APIResponse<T: Codable>: Codable, @unchecked Sendable {
    var data: T
}

// MARK: - APIError

struct APIError: Codable, @unchecked Sendable {
    var code: String
    var message: String
    var details: [String: String]?
}

// MARK: - APIErrorResponse

struct APIErrorResponse: Codable, @unchecked Sendable {
    var error: APIError
}

// MARK: - ChallengeListData

struct ChallengeListData: Codable, @unchecked Sendable {
    var challenges: [ChallengeListItemDTO]
    var total: Int
    var limit: Int
    var offset: Int
}

// MARK: - ChallengeListItemDTO

struct ChallengeListItemDTO: Codable, Identifiable, @unchecked Sendable {
    var id: UUID
    var name: String
    var description: String
    var category: ChallengeCategory
    var type: ChallengeType
    var participantCount: Int
    var isActive: Bool
}

// MARK: - ChallengeDefinitionDTO

struct ChallengeDefinitionDTO: Codable, Identifiable, @unchecked Sendable {
    var id: UUID
    var version: Int
    var name: String
    var description: String
    var author: String
    var category: ChallengeCategory
    var type: ChallengeType
    var configuration: ChallengeConfigurationDTO
    var badges: [ChallengeBadgeDTO]?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - ChallengeConfigurationDTO

struct ChallengeConfigurationDTO: Codable, Equatable, @unchecked Sendable {
    var goals: ChallengeGoalsDTO
    var tiers: [ChallengeTierDTO]?
    var qualificationCriteria: QualificationCriteriaDTO
    var scoring: ScoringConfigDTO
    var historicalQsosAllowed: Bool
}

// MARK: - ChallengeGoalsDTO

struct ChallengeGoalsDTO: Codable, Equatable, @unchecked Sendable {
    var type: String
    var items: [ChallengeGoalItemDTO]?
    var target: Int?
    var unit: String?
}

// MARK: - ChallengeGoalItemDTO

struct ChallengeGoalItemDTO: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
}

// MARK: - ChallengeTierDTO

struct ChallengeTierDTO: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var threshold: Int
}

// MARK: - QualificationCriteriaDTO

struct QualificationCriteriaDTO: Codable, Equatable, @unchecked Sendable {
    var bands: [String]?
    var modes: [String]?
    var requiredFields: [String]?
    var dateRange: DateRangeDTO?
    var matchRules: [MatchRuleDTO]?
}

// MARK: - DateRangeDTO

struct DateRangeDTO: Codable, Equatable, @unchecked Sendable {
    var start: Date
    var end: Date
}

// MARK: - MatchRuleDTO

struct MatchRuleDTO: Codable, Equatable, @unchecked Sendable {
    var qsoField: String
    var goalField: String
}

// MARK: - ScoringConfigDTO

struct ScoringConfigDTO: Codable, Equatable, @unchecked Sendable {
    var method: String
    var displayFormat: String?
}

// MARK: - ChallengeBadgeDTO

struct ChallengeBadgeDTO: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var tierId: String?
}

// MARK: - LeaderboardData

struct LeaderboardData: Codable, @unchecked Sendable {
    var leaderboard: [LeaderboardEntry]
    var total: Int
    var userPosition: LeaderboardUserPosition?
    var lastUpdated: Date
}

// MARK: - LeaderboardUserPosition

struct LeaderboardUserPosition: Codable, Equatable, @unchecked Sendable {
    var rank: Int
    var callsign: String
    var score: Int
}

// MARK: - JoinChallengeRequest

struct JoinChallengeRequest: Codable, @unchecked Sendable {
    var callsign: String
    var deviceName: String
    var inviteToken: String?
}

// MARK: - JoinChallengeData

struct JoinChallengeData: Codable, @unchecked Sendable {
    var participationId: UUID
    var deviceToken: String
    var joinedAt: Date
    var status: String
    var historicalAllowed: Bool
}

// MARK: - ProgressReportRequest

struct ProgressReportRequest: Codable, @unchecked Sendable {
    var completedGoals: [String]
    var currentValue: Int
    var qualifyingQsoCount: Int
    var lastQsoDate: Date?
}

// MARK: - ProgressReportData

struct ProgressReportData: Codable, @unchecked Sendable {
    var accepted: Bool
    var serverProgress: ServerProgress
    var newBadges: [String]?
}

// MARK: - ParticipatingChallengeDTO

struct ParticipatingChallengeDTO: Codable, Identifiable, @unchecked Sendable {
    var participationId: UUID
    var challengeId: UUID
    var challengeName: String
    var joinedAt: Date
    var status: String

    var id: UUID {
        participationId
    }
}
