import UIKit

// MARK: - SpotTier

/// The Band Scope priority tier (spec §2): every spot gets exactly one.
/// `needed` beats `club` beats `pota` beats `rbn`. Tier drives dot color,
/// scrubber-mark color, chip color, and glow in BOTH lenses.
enum SpotTier: Int, Comparable {
    case rbn = 0
    case pota
    case club
    case needed

    // MARK: Internal

    static func < (lhs: SpotTier, rhs: SpotTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension NeedCategory {
    /// Stable key matching Rust `NeedCategory::key()` — what profile
    /// `need_categories` select on.
    var profileKey: String {
        switch self {
        case .dxccEntity: "dxcc"
        case .dxccBandSlot: "dxcc_band"
        case .wasState: "was"
        case .wasStateMode: "was_mode"
        case .potaNewPark: "pota_new_park"
        case .potaActivatorState: "pota_activator_state"
        case .potaActivatorEntity: "pota_activator_entity"
        case .wwffNewReference: "wwff"
        case .custom: "custom"
        }
    }
}

extension EnrichedSpot {
    /// The needs that count under the active profile — the engine matches
    /// ALL globally-enabled goals; the profile selects from them (so the
    /// Hunter Log's needs are never disturbed by a Band Scope profile).
    func profileNeeds(for profile: GoalProfile) -> [MatchedNeed] {
        let keys = profile.needCategoryKeys
        guard !keys.isEmpty else {
            return matchedNeeds
        }
        return matchedNeeds.filter { keys.contains($0.category.profileKey) }
    }

    /// Tier assignment (spec §2). Club detection is SKCC-roster-backed in
    /// v1; LICW/CWOps identity surfaces in the peek sheet via enrichment.
    func tier(for profile: GoalProfile) -> SpotTier {
        if !profileNeeds(for: profile).isEmpty {
            return .needed
        }
        if skccMember != nil, profile.clubs.contains(.skcc) {
            return .club
        }
        // Skimmer/automated sources carry no human intent; everything
        // else is a human spot (§2's `pota` tier).
        return spot.source.isAutomated ? .rbn : .pota
    }

    /// The single goal chip for a row (§9): the highest-priority need
    /// under the active profile, or nothing. Chips say why the user
    /// cares, never what the spot is.
    func goalChip(for profile: GoalProfile) -> MatchedNeed? {
        profileNeeds(for: profile).max { lhs, rhs in
            lhs.priority < rhs.priority
        }
    }
}

extension SpotSource {
    /// Skimmer/automated feeds — no human hit the spot button.
    var isAutomated: Bool {
        self == .rbn || self == .pskr
    }
}
