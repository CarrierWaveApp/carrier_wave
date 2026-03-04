// WWFF Awards
//
// Award tier definitions for WWFF activator and hunter awards.
// Based on WWFF Global Rules V5.10.

import Foundation

// MARK: - WWFFAwardCategory

/// Top-level award categories in the WWFF program.
enum WWFFAwardCategory: String, CaseIterable, Sendable {
    case activatorReferences
    case activatorPoints
    case activatorDXCC
    case activatorContinents
    case hunterReferences
    case hunterDXCC
    case hunterContinents
    case parkToPark
}

// MARK: - WWFFAwardTier

/// A specific tier within a WWFF award category.
struct WWFFAwardTier: Sendable, Identifiable {
    let id: String
    let category: WWFFAwardCategory
    let label: String
    let threshold: Int
    let isSpecial: Bool // e.g., "novice" tier for hunters

    init(
        category: WWFFAwardCategory,
        label: String,
        threshold: Int,
        isSpecial: Bool = false
    ) {
        self.id = "\(category.rawValue)-\(threshold)"
        self.category = category
        self.label = label
        self.threshold = threshold
        self.isSpecial = isSpecial
    }
}

// MARK: - WWFFRules

/// WWFF program rules and constants from the Global Rules V5.10.
enum WWFFRules {
    /// Minimum QSOs required for a valid activation.
    static let activationMinQSOs = 44

    /// Maximum points earnable per reference per year.
    static let maxPointsPerReferencePerYear = 10

    /// QSOs required for one activator point.
    static let qsosPerActivatorPoint = 44

    /// Minimum QSOs for club league qualification.
    static let clubLeagueMinQSOs = 200

    /// Contacts via repeaters, IRLP, Echolink do not count.
    static let invalidModes: Set<String> = ["ECHOLINK", "IRLP"]

    /// Activators may only activate one reference at a time.
    static let maxSimultaneousReferences = 1

    // MARK: - Activator Reference Award Tiers

    /// Tiers: 11, 22, 33, 44, 55, 66, 77, 88, 99, 110, ...
    static func activatorReferenceTiers(upTo count: Int = 220) -> [WWFFAwardTier] {
        var tiers: [WWFFAwardTier] = []
        var threshold = 11
        while threshold <= max(count + 11, 110) {
            tiers.append(WWFFAwardTier(
                category: .activatorReferences,
                label: "\(threshold) References",
                threshold: threshold
            ))
            threshold += 11
        }
        return tiers
    }

    // MARK: - Activator Points Award Tiers

    /// Tiers: 11, 22, 44, 88 points, then higher levels.
    static let activatorPointsTiers: [WWFFAwardTier] = [
        WWFFAwardTier(category: .activatorPoints, label: "11 Points", threshold: 11),
        WWFFAwardTier(category: .activatorPoints, label: "22 Points", threshold: 22),
        WWFFAwardTier(category: .activatorPoints, label: "44 Points", threshold: 44),
        WWFFAwardTier(category: .activatorPoints, label: "88 Points", threshold: 88),
        WWFFAwardTier(category: .activatorPoints, label: "176 Points", threshold: 176),
        WWFFAwardTier(category: .activatorPoints, label: "352 Points", threshold: 352),
    ]

    // MARK: - Activator DXCC Tiers

    /// Entry: 3 entities, then upgrades every 3 entities.
    static func activatorDXCCTiers(upTo count: Int = 30) -> [WWFFAwardTier] {
        var tiers: [WWFFAwardTier] = []
        var threshold = 3
        while threshold <= max(count + 3, 15) {
            tiers.append(WWFFAwardTier(
                category: .activatorDXCC,
                label: "\(threshold) DXCC Entities",
                threshold: threshold
            ))
            threshold += 3
        }
        return tiers
    }

    // MARK: - Activator Continents Tiers

    /// 3, 6, 7 continents (Antarctica counts separately).
    static let activatorContinentsTiers: [WWFFAwardTier] = [
        WWFFAwardTier(category: .activatorContinents, label: "3 Continents", threshold: 3),
        WWFFAwardTier(category: .activatorContinents, label: "6 Continents", threshold: 6),
        WWFFAwardTier(category: .activatorContinents, label: "7 Continents", threshold: 7),
    ]

    // MARK: - Hunter Reference Award Tiers

    /// Novice: 10, then 44, 88, ..., 396, then 444, 544, 644, ...
    static func hunterReferenceTiers(upTo count: Int = 1_000) -> [WWFFAwardTier] {
        var tiers: [WWFFAwardTier] = []
        tiers.append(WWFFAwardTier(
            category: .hunterReferences,
            label: "Novice (10)",
            threshold: 10,
            isSpecial: true
        ))
        var threshold = 44
        while threshold <= 396 {
            tiers.append(WWFFAwardTier(
                category: .hunterReferences,
                label: "\(threshold) References",
                threshold: threshold
            ))
            threshold += 44
        }
        threshold = 444
        while threshold <= max(count + 100, 1_000) {
            tiers.append(WWFFAwardTier(
                category: .hunterReferences,
                label: "\(threshold) References",
                threshold: threshold
            ))
            threshold += 100
        }
        return tiers
    }

    // MARK: - Hunter DXCC Tiers

    /// Entry: 10, upgrades every 10.
    static func hunterDXCCTiers(upTo count: Int = 100) -> [WWFFAwardTier] {
        var tiers: [WWFFAwardTier] = []
        var threshold = 10
        while threshold <= max(count + 10, 50) {
            tiers.append(WWFFAwardTier(
                category: .hunterDXCC,
                label: "\(threshold) DXCC Entities",
                threshold: threshold
            ))
            threshold += 10
        }
        return tiers
    }

    // MARK: - Hunter Continents Tiers

    static let hunterContinentsTiers: [WWFFAwardTier] = [
        WWFFAwardTier(category: .hunterContinents, label: "3 Continents", threshold: 3),
        WWFFAwardTier(category: .hunterContinents, label: "6 Continents", threshold: 6),
        WWFFAwardTier(category: .hunterContinents, label: "7 Continents", threshold: 7),
    ]

    // MARK: - Park-to-Park Tiers

    /// Entry: 10, then 44, 88, ...
    static func parkToParkTiers(upTo count: Int = 440) -> [WWFFAwardTier] {
        var tiers: [WWFFAwardTier] = []
        tiers.append(WWFFAwardTier(
            category: .parkToPark,
            label: "10 P2P QSOs",
            threshold: 10,
            isSpecial: true
        ))
        var threshold = 44
        while threshold <= max(count + 44, 220) {
            tiers.append(WWFFAwardTier(
                category: .parkToPark,
                label: "\(threshold) P2P QSOs",
                threshold: threshold
            ))
            threshold += 44
        }
        return tiers
    }

    // MARK: - Tier Lookup

    /// Find the current and next tier for a given count in a category.
    static func progress(
        for count: Int,
        category: WWFFAwardCategory
    ) -> (current: WWFFAwardTier?, next: WWFFAwardTier?) {
        let tiers = allTiers(for: category, upTo: count)
        let achieved = tiers.last { $0.threshold <= count }
        let next = tiers.first { $0.threshold > count }
        return (current: achieved, next: next)
    }

    /// Get all tiers for a category, generating enough to cover the count.
    static func allTiers(
        for category: WWFFAwardCategory,
        upTo count: Int = 0
    ) -> [WWFFAwardTier] {
        switch category {
        case .activatorReferences:
            return activatorReferenceTiers(upTo: count)
        case .activatorPoints:
            return activatorPointsTiers
        case .activatorDXCC:
            return activatorDXCCTiers(upTo: count)
        case .activatorContinents:
            return activatorContinentsTiers
        case .hunterReferences:
            return hunterReferenceTiers(upTo: count)
        case .hunterDXCC:
            return hunterDXCCTiers(upTo: count)
        case .hunterContinents:
            return hunterContinentsTiers
        case .parkToPark:
            return parkToParkTiers(upTo: count)
        }
    }
}
