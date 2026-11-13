// Need Types
//
// Data models for the Smart Spot Recommendations feature.
// Defines need categories, matched needs, priority levels, and the frozen
// NeedsSnapshot that flows from NeedsEngine to SpotNeedsMatcher.
//
// All types are nonisolated Sendable value types — safe to use across actors.

import Foundation

// MARK: - NeedCategory

/// What the operator still needs — each variant carries enough context
/// for display labels and spot matching.
nonisolated enum NeedCategory: Hashable {
    // Phase 1: DXCC + WAS
    case dxccEntity(entity: String)
    case dxccBandSlot(entity: String, band: String)
    case wasState(state: String)
    case wasStateMode(state: String, mode: String)

    // Phase 2: POTA + WWFF + Challenges
    case potaNewPark
    case potaActivatorState(state: String)
    case potaActivatorEntity(entity: String)
    case wwffNewReference

    /// Phase 3: Custom user-defined
    case custom(pattern: String, label: String)
}

// MARK: - NeedPriority

/// Urgency level for a matched need, determines notification behavior.
nonisolated enum NeedPriority: Int, Comparable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2

    // MARK: Internal

    static func < (lhs: NeedPriority, rhs: NeedPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - MatchedNeed

/// A need matched against a specific spot.
nonisolated struct MatchedNeed: Hashable, Identifiable {
    let id = UUID()
    let category: NeedCategory
    let label: String
    let priority: NeedPriority

    static func == (lhs: MatchedNeed, rhs: MatchedNeed) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - BandSlotKey

/// Composite key for (entity, band) DXCC band-slot tracking.
nonisolated struct BandSlotKey: Hashable {
    let entity: String
    let band: String
}

// MARK: - DXCCNeeds

/// DXCC entities and band slots the operator has not yet worked.
nonisolated struct DXCCNeeds {
    static let empty = DXCCNeeds(
        allTimeWorked: [],
        bandSlotsWorked: [],
        totalKnownEntities: 0,
        gridSquare: nil
    )

    /// Entity primary prefixes already worked (any band).
    let allTimeWorked: Set<String>

    /// (entity, band) pairs already worked.
    let bandSlotsWorked: Set<BandSlotKey>

    /// Total known entities from CTY.dat for progress display.
    let totalKnownEntities: Int

    /// Operator's grid square used for this DXCC computation (nil if mixed).
    let gridSquare: String?

    var entitiesWorkedCount: Int {
        allTimeWorked.count
    }

    var entitiesRemaining: Int {
        max(0, totalKnownEntities - allTimeWorked.count)
    }

    /// Next DXCC milestone tier based on current count.
    var nextTier: DXCCTier {
        DXCCTier.next(for: allTimeWorked.count)
    }
}

// MARK: - DXCCTier

/// DXCC award tiers — 100 confirmed entities is the base DXCC award.
nonisolated struct DXCCTier {
    // MARK: Internal

    let threshold: Int
    let name: String?

    static func next(for count: Int) -> DXCCTier {
        for (threshold, name) in tiers where threshold > count {
            return DXCCTier(threshold: threshold, name: name)
        }
        return DXCCTier(threshold: count, name: nil)
    }

    // MARK: Private

    private static let tiers: [(Int, String)] = [
        (100, "DXCC"),
        (150, "150"),
        (200, "200"),
        (250, "250"),
        (300, "300"),
        (325, "Honor Roll"),
        (340, "Top of Honor Roll"),
    ]
}

// MARK: - WASNeeds

/// Primary subdivisions (states, provinces, counties, prefectures, …)
/// the operator has not yet worked. Originally Worked All States (USA),
/// but generalized so that UK-counties, Japan JCC, German DOK, and other
/// national-subdivision awards can reuse the same pipeline later.
nonisolated struct WASNeeds {
    static let empty = WASNeeds(
        country: "USA",
        subdivisionTerm: "states",
        statesWorked: [],
        statesMissing: USStatesReference.allStates,
        perModeWorked: [:]
    )

    /// Country this award applies to (ADIF country name). For USA the
    /// award is classic WAS; other values are reserved for future
    /// subdivision-based awards. When `statesMissing` is empty the
    /// award is complete regardless of country.
    let country: String

    /// Plural noun for the tracked subdivision — "states", "provinces",
    /// "counties", etc. — used for display so UI copy is not
    /// hardcoded to "states".
    let subdivisionTerm: String

    /// Subdivision codes already worked (any mode).
    let statesWorked: Set<String>

    /// Subdivisions still missing.
    let statesMissing: Set<String>

    /// Per-mode breakdown: mode → subdivisions worked on that mode.
    let perModeWorked: [String: Set<String>]

    var isComplete: Bool {
        statesMissing.isEmpty
    }

    var statesWorkedCount: Int {
        statesWorked.count
    }
}

// MARK: - POTAHunterNeeds

/// POTA parks the operator has not yet hunted.
nonisolated struct POTAHunterNeeds {
    static let empty = POTAHunterNeeds(
        parksWorked: [], nextTierThreshold: 0, nextTierName: nil
    )

    /// Park references already hunted.
    let parksWorked: Set<String>
    /// Next hunter tier threshold.
    let nextTierThreshold: Int
    /// Next tier name.
    let nextTierName: String?

    /// Parks remaining for next tier.
    var parksRemaining: Int {
        max(0, nextTierThreshold - parksWorked.count)
    }
}

// MARK: - POTAActivatorNeeds

/// States and entities not yet activated for POTA awards.
nonisolated struct POTAActivatorNeeds {
    static let empty = POTAActivatorNeeds(
        statesMissing: [], entitiesWorked: 0, nextEntityTierThreshold: 0
    )

    let statesMissing: Set<String>
    let entitiesWorked: Int
    let nextEntityTierThreshold: Int
}

// MARK: - WWFFHunterNeeds

/// WWFF references the operator has not yet hunted.
nonisolated struct WWFFHunterNeeds {
    static let empty = WWFFHunterNeeds(
        referencesWorked: [], nextTierThreshold: 0, nextTierName: nil
    )

    let referencesWorked: Set<String>
    let nextTierThreshold: Int
    let nextTierName: String?

    var referencesRemaining: Int {
        max(0, nextTierThreshold - referencesWorked.count)
    }
}

// MARK: - NeedsSnapshot

/// Frozen, Sendable snapshot of all operator needs.
/// Produced by NeedsEngine, consumed by SpotNeedsMatcher.
nonisolated struct NeedsSnapshot {
    static let empty = NeedsSnapshot(
        dxcc: .empty,
        was: .empty,
        potaHunter: .empty,
        potaActivator: .empty,
        wwffHunter: .empty,
        customPatterns: [],
        modeFamiliesWorked: [],
        generatedAt: .distantPast
    )

    let dxcc: DXCCNeeds
    let was: WASNeeds
    let potaHunter: POTAHunterNeeds
    let potaActivator: POTAActivatorNeeds
    let wwffHunter: WWFFHunterNeeds
    let customPatterns: [CustomNeedPattern]

    /// Mode families (e.g. "phone", "cw", "digital") the operator has
    /// actually worked. Used to suppress notifications for modes the
    /// operator doesn't use.
    let modeFamiliesWorked: Set<String>

    let generatedAt: Date

    var isEmpty: Bool {
        dxcc.entitiesRemaining == 0
            && was.isComplete
            && potaHunter.parksRemaining == 0
            && wwffHunter.referencesRemaining == 0
            && customPatterns.isEmpty
    }
}

// MARK: - CustomNeedPattern

/// A user-defined need pattern for spot matching.
nonisolated struct CustomNeedPattern: Hashable, Identifiable {
    enum PatternType: String, Codable, Hashable {
        case callsign
        case entity
        case state
        case parkRef
    }

    let id: UUID
    let pattern: String
    let patternType: PatternType
    let label: String

    /// Test whether a value matches this pattern (supports * wildcards).
    func matches(_ value: String) -> Bool {
        let upper = value.uppercased()
        let pat = pattern.uppercased()

        if pat.contains("*") {
            let parts = pat.components(separatedBy: "*")
            guard let prefix = parts.first else {
                return true
            }
            if !parts.last!.isEmpty {
                return upper.hasPrefix(prefix) && upper.hasSuffix(parts.last!)
            }
            return upper.hasPrefix(prefix)
        }
        return upper == pat
    }
}

// MARK: - USStatesReference

/// Reference set of all 50 US states for WAS computation.
nonisolated enum USStatesReference {
    static let allStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
    ]
}
