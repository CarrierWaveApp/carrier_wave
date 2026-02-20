import Foundation
import SwiftData

/// Nonisolated helper functions to work around @MainActor Codable conformance issues
nonisolated private func decodeConfiguration(from data: Data) -> ChallengeConfiguration? {
    try? JSONDecoder().decode(ChallengeConfiguration.self, from: data)
}

nonisolated private func encodeConfiguration(_ config: ChallengeConfiguration) throws -> Data {
    try JSONEncoder().encode(config)
}

// MARK: - ChallengeDefinition

@Model
nonisolated final class ChallengeDefinition {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        sourceURL: String,
        version: Int = 1,
        name: String,
        descriptionText: String,
        author: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        type: ChallengeType,
        configurationData: Data,
        source: ChallengeSource? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.version = version
        self.name = name
        self.descriptionText = descriptionText
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        typeRawValue = type.rawValue
        self.configurationData = configurationData
        self.source = source
    }

    // MARK: Internal

    var id = UUID()
    var sourceURL = ""
    var version = 1

    // Metadata (stored directly for queryability)
    var name = ""
    var descriptionText = ""
    var author = ""
    var createdAt = Date()
    var updatedAt = Date()

    var typeRawValue = ChallengeType.collection.rawValue

    /// Configuration stored as JSON
    var configurationData = Data()

    var source: ChallengeSource?

    /// Non-optional wrapper for CloudKit-required optional relationship
    var participations: [ChallengeParticipation] {
        get { participationsRelation ?? [] }
        set { participationsRelation = newValue }
    }

    var type: ChallengeType {
        get { ChallengeType(rawValue: typeRawValue) ?? .collection }
        set { typeRawValue = newValue.rawValue }
    }

    // MARK: - Configuration Access

    var configuration: ChallengeConfiguration? {
        decodeConfiguration(from: configurationData)
    }

    var goals: [ChallengeGoal] {
        configuration?.goals ?? []
    }

    var tiers: [ChallengeTier] {
        configuration?.tiers ?? []
    }

    var criteria: QualificationCriteria? {
        configuration?.criteria
    }

    var scoring: ScoringConfig? {
        configuration?.scoring
    }

    var timeConstraints: TimeConstraints? {
        configuration?.timeConstraints
    }

    var badges: [ChallengeBadge] {
        configuration?.badges ?? []
    }

    var historicalQSOsAllowed: Bool {
        configuration?.historicalQSOsAllowed ?? false
    }

    // MARK: - Convenience

    /// Total number of goals for collection challenges
    var totalGoals: Int {
        goals.count
    }

    /// Target value for cumulative challenges
    var targetValue: Int? {
        goals.first?.targetValue
    }

    /// Whether this challenge has time constraints
    var isTimeBounded: Bool {
        timeConstraints != nil
    }

    /// Time remaining for time-bounded challenges
    var timeRemaining: TimeInterval? {
        guard let constraints = timeConstraints,
              let endDate = constraints.endDate
        else {
            return nil
        }
        let remaining = endDate.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    /// Whether the challenge has ended
    var hasEnded: Bool {
        guard let constraints = timeConstraints,
              let endDate = constraints.endDate
        else {
            return false
        }
        return Date() > endDate
    }

    /// Sorted tiers by order
    var sortedTiers: [ChallengeTier] {
        tiers.sorted { $0.order < $1.order }
    }

    // MARK: Private

    @Relationship(deleteRule: .cascade, inverse: \ChallengeParticipation.challengeDefinition)
    private var participationsRelation: [ChallengeParticipation]?
}

// MARK: - Factory

extension ChallengeDefinition {
    /// Create from API DTO
    static func from(
        dto: ChallengeDefinitionDTO,
        source: ChallengeSource?
    ) throws -> ChallengeDefinition {
        let configData = try buildConfigurationData(from: dto)

        return ChallengeDefinition(
            id: dto.id,
            sourceURL: source?.url ?? "",
            version: dto.version,
            name: dto.name,
            descriptionText: dto.description,
            author: dto.author,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            type: dto.type,
            configurationData: configData,
            source: source
        )
    }

    /// Update from API DTO
    func update(from dto: ChallengeDefinitionDTO) throws {
        version = dto.version
        name = dto.name
        descriptionText = dto.description
        author = dto.author
        updatedAt = dto.updatedAt
        configurationData = try Self.buildConfigurationData(from: dto)
    }

    /// Build configuration data from DTO
    private static func buildConfigurationData(from dto: ChallengeDefinitionDTO) throws -> Data {
        let config = ChallengeConfiguration(
            goals: buildGoals(from: dto),
            tiers: buildTiers(from: dto),
            criteria: buildCriteria(from: dto),
            scoring: buildScoring(from: dto),
            timeConstraints: nil,
            badges: buildBadges(from: dto),
            historicalQSOsAllowed: dto.configuration.historicalQsosAllowed,
            inviteConfig: nil
        )
        return try encodeConfiguration(config)
    }

    private static func buildGoals(from dto: ChallengeDefinitionDTO) -> [ChallengeGoal] {
        dto.configuration.goals.items?.map { item in
            ChallengeGoal(
                id: item.id,
                name: item.name,
                category: nil,
                metadata: nil,
                targetValue: dto.configuration.goals.target,
                unit: dto.configuration.goals.unit
            )
        } ?? []
    }

    private static func buildTiers(from dto: ChallengeDefinitionDTO) -> [ChallengeTier]? {
        dto.configuration.tiers?.enumerated().map { index, tier in
            ChallengeTier(
                id: tier.id,
                name: tier.name,
                threshold: tier.threshold,
                badgeId: dto.badges?.first { $0.tierId == tier.id }?.id,
                order: index
            )
        }
    }

    private static func buildCriteria(from dto: ChallengeDefinitionDTO) -> QualificationCriteria {
        let qc = dto.configuration.qualificationCriteria
        return QualificationCriteria(
            bands: qc.bands,
            modes: qc.modes,
            requiredFields: qc.requiredFields?.map {
                FieldRequirement(fieldName: $0, mustExist: true, pattern: nil)
            },
            dateRange: qc.dateRange.map {
                ChallengeDateRange(startDate: $0.start, endDate: $0.end)
            },
            matchRules: qc.matchRules?.map {
                MatchRule(
                    qsoField: $0.qsoField,
                    goalField: $0.goalField,
                    transformation: nil,
                    validationRegex: nil
                )
            }
        )
    }

    private static func buildScoring(from dto: ChallengeDefinitionDTO) -> ScoringConfig {
        ScoringConfig(
            method: ScoringMethod(rawValue: dto.configuration.scoring.method) ?? .count,
            weights: nil,
            tiebreaker: nil,
            displayFormat: dto.configuration.scoring.displayFormat
        )
    }

    private static func buildBadges(from dto: ChallengeDefinitionDTO) -> [ChallengeBadge]? {
        dto.badges?.map {
            ChallengeBadge(
                id: $0.id,
                name: $0.name,
                description: "",
                imageURL: "",
                tier: $0.tierId
            )
        }
    }
}
