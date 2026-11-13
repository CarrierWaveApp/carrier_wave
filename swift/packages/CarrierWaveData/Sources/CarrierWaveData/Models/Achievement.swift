import Foundation

// MARK: - Achievement

/// Catalog entry describing a single profile badge users can collect.
/// Mirrors the server `achievements` table.
public struct Achievement: Codable, Hashable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        id: String,
        name: String,
        description: String,
        category: Category,
        tier: Tier?,
        iconName: String,
        accentHex: String?,
        awardMethod: AwardMethod,
        secret: Bool,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.tier = tier
        self.iconName = iconName
        self.accentHex = accentHex
        self.awardMethod = awardMethod
        self.secret = secret
        self.sortOrder = sortOrder
    }

    // MARK: Public

    public enum Category: String, Codable, Sendable, CaseIterable {
        case creator
        case community
        case activity
        case ecosystem
        case streak
        case quirky
        case unknown

        // MARK: Lifecycle

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Category(rawValue: raw) ?? .unknown
        }
    }

    public enum Tier: String, Codable, Sendable {
        case bronze
        case silver
        case gold
        case platinum
    }

    public enum AwardMethod: String, Codable, Sendable {
        case manual
        case auto
        case signal
        case unknown

        // MARK: Lifecycle

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = AwardMethod(rawValue: raw) ?? .unknown
        }
    }

    public let id: String
    public let name: String
    public let description: String
    public let category: Category
    public let tier: Tier?
    public let iconName: String
    public let accentHex: String?
    public let awardMethod: AwardMethod
    public let secret: Bool
    public let sortOrder: Int
}

// MARK: - UserAchievement

/// A single award: a callsign earned a specific achievement at some point in time.
public struct UserAchievement: Codable, Hashable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        callsign: String,
        achievementId: String,
        awardedAt: Date,
        awardedBy: String?
    ) {
        self.id = id
        self.callsign = callsign
        self.achievementId = achievementId
        self.awardedAt = awardedAt
        self.awardedBy = awardedBy
    }

    // MARK: Public

    public let id: UUID
    public let callsign: String
    public let achievementId: String
    public let awardedAt: Date
    public let awardedBy: String?
}

// MARK: - AchievementCatalogResponse

public struct AchievementCatalogResponse: Codable, Sendable {
    public let achievements: [Achievement]
}

// MARK: - UserAchievementsResponse

public struct UserAchievementsResponse: Codable, Sendable {
    public let callsign: String
    public let awards: [UserAchievement]
}
