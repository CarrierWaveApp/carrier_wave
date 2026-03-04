import CarrierWaveData
import Foundation

// MARK: - ChallengeType

enum ChallengeType: String, Codable, CaseIterable, @unchecked Sendable {
    case collection
    case cumulative
    case timeBounded
}

// MARK: - ParticipationStatus

enum ParticipationStatus: String, Codable, CaseIterable, @unchecked Sendable {
    case active
    case completed
    case left
    case expired
}

// MARK: - ChallengeSourceType

enum ChallengeSourceType: String, Codable, CaseIterable, @unchecked Sendable {
    case official
    case community
    case invite
}

// MARK: - ScoringMethod

enum ScoringMethod: String, Codable, CaseIterable, @unchecked Sendable {
    case percentage
    case count
    case points
    case weighted
}

// MARK: - TimeConstraintType

enum TimeConstraintType: String, Codable, @unchecked Sendable {
    case calendar
    case relative
}

// MARK: - ChallengeMetadata

struct ChallengeMetadata: Codable, Equatable, @unchecked Sendable {
    var name: String
    var description: String
    var author: String
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - ChallengeGoal

struct ChallengeGoal: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var category: String?
    var metadata: [String: String]?

    // For cumulative challenges
    var targetValue: Int?
    var unit: String?
}

// MARK: - ChallengeTier

struct ChallengeTier: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var threshold: Int
    var badgeId: String?
    var order: Int
}

// MARK: - QualificationCriteria

struct QualificationCriteria: Codable, Equatable, @unchecked Sendable {
    var bands: [String]?
    var modes: [String]?
    var requiredFields: [FieldRequirement]?
    var dateRange: ChallengeDateRange?
    var matchRules: [MatchRule]?
}

// MARK: - FieldRequirement

struct FieldRequirement: Codable, Equatable, @unchecked Sendable {
    var fieldName: String
    var mustExist: Bool
    var pattern: String?
}

// MARK: - ChallengeDateRange

struct ChallengeDateRange: Codable, Equatable, @unchecked Sendable {
    var startDate: Date
    var endDate: Date
}

// MARK: - MatchRule

struct MatchRule: Codable, Equatable, @unchecked Sendable {
    var qsoField: String
    var goalField: String
    var transformation: MatchTransformation?
    var validationRegex: String?
}

// MARK: - MatchTransformation

enum MatchTransformation: String, Codable, @unchecked Sendable {
    case uppercase
    case lowercase
    case stripPrefix
    case stripSuffix
}

// MARK: - ScoringConfig

struct ScoringConfig: Codable, Equatable, @unchecked Sendable {
    var method: ScoringMethod
    var weights: [WeightRule]?
    var tiebreaker: TiebreakerRule?
    var displayFormat: String?
}

// MARK: - WeightRule

struct WeightRule: Codable, Equatable, @unchecked Sendable {
    var condition: String
    var multiplier: Double
}

// MARK: - TiebreakerRule

enum TiebreakerRule: String, Codable, @unchecked Sendable {
    case earliestCompletion
    case mostRecent
    case alphabetical
}

// MARK: - TimeConstraints

struct TimeConstraints: Codable, Equatable, @unchecked Sendable {
    var type: TimeConstraintType
    var startDate: Date?
    var endDate: Date?
    var durationSeconds: Int?
    var timezone: String?
}

// MARK: - ChallengeBadge

struct ChallengeBadge: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var description: String
    var imageURL: String
    var tier: String?
}

// MARK: - InviteConfig

struct InviteConfig: Codable, Equatable, @unchecked Sendable {
    var maxParticipants: Int?
    var expiresAt: Date?
    var participantCount: Int
}

// MARK: - ChallengeCategory

enum ChallengeCategory: String, Codable, CaseIterable, @unchecked Sendable {
    case award
    case event
    case club
    case personal
    case other
}
