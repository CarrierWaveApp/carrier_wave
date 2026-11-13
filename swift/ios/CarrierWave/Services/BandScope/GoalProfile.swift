import CarrierWaveCwFfi
import UIKit

// MARK: - GoalProfile

/// A Band Scope goal profile — spec §16: filtering and goal config are ONE
/// system. A profile decides which goals compute the `needed` tier, which
/// club memberships light the `club` tier, and the base include/exclude
/// predicate for the feed. Compilation to SQL happens in Rust
/// (`compileProfileQueries`); this type is the Codable host twin.
struct GoalProfile: Codable, Equatable, Identifiable {
    enum Predicate: String, Codable {
        case all
        case parks
        case dxccNeeded
        case clubMembers
        case neededOnly
    }

    /// Clubs the profile recognizes for the `club` tier / club predicate.
    enum Club: String, Codable, CaseIterable {
        case skcc
        case licw
        case cwops
    }

    /// Goals that compute `needed` under this profile. Maps to the
    /// `NeedCategory` keys the Rust needs matcher writes into
    /// `scope.spot_needs`.
    enum Goal: String, Codable, CaseIterable {
        case dxcc
        case was
        case parks
        case wwff
        case custom

        // MARK: Internal

        /// Rust `NeedCategory::key()` values this goal covers.
        var categoryKeys: [String] {
            switch self {
            case .dxcc: ["dxcc", "dxcc_band"]
            case .was: ["was", "was_mode"]
            case .parks: ["pota_new_park", "pota_activator_state", "pota_activator_entity"]
            case .wwff: ["wwff"]
            case .custom: ["custom"]
            }
        }
    }

    // MARK: - Built-ins (spec §16)

    static let everything = GoalProfile(
        id: "builtin.everything",
        name: "Everything",
        predicate: .all,
        goals: Goal.allCases,
        clubs: Club.allCases
    )

    static let parks = GoalProfile(
        id: "builtin.parks",
        name: "Parks",
        predicate: .parks,
        goals: [.parks, .wwff],
        clubs: []
    )

    static let dxcc = GoalProfile(
        id: "builtin.dxcc",
        name: "DXCC",
        predicate: .dxccNeeded,
        goals: [.dxcc],
        clubs: []
    )

    static let clubSkeds = GoalProfile(
        id: "builtin.clubs",
        name: "Club skeds",
        predicate: .clubMembers,
        goals: Goal.allCases,
        clubs: Club.allCases
    )

    static let builtIns: [GoalProfile] = [.everything, .parks, .dxcc, .clubSkeds]

    var id: String
    var name: String
    var predicate: Predicate
    var goals: [Goal]
    var clubs: [Club]

    var isBuiltIn: Bool {
        Self.builtIns.contains { $0.id == id }
    }

    /// The `NeedCategory` keys that count as needed under this profile.
    var needCategoryKeys: Set<String> {
        Set(goals.flatMap(\.categoryKeys))
    }

    var ffiProfile: FfiGoalProfile {
        let basePredicate: FfiBasePredicate = switch predicate {
        case .all: .all
        case .parks: .parks
        case .dxccNeeded: .dxccNeeded
        case .clubMembers: .clubMembers
        case .neededOnly: .neededOnly
        }
        return FfiGoalProfile(
            id: id,
            name: name,
            basePredicate: basePredicate,
            clubs: clubs.map(\.rawValue),
            needCategories: needCategoryKeys.sorted()
        )
    }
}

// MARK: - QuickToggles

/// Quick-toggle state within any profile (spec §17).
struct QuickToggles: Codable, Equatable {
    /// Radio-mode filter groups (hide in Heard, dim in Scope).
    enum ModeGroup: String, Codable, CaseIterable {
        case cw
        case phone
        case digital

        // MARK: Internal

        /// Chip / menu label.
        var label: String {
            switch self {
            case .cw: "CW"
            case .phone: "SSB"
            case .digital: "DIG"
            }
        }

        /// Spot mode strings this group covers (compared uppercase in SQL).
        var modes: [String] {
            switch self {
            case .cw: ["CW"]
            case .phone: ["SSB", "USB", "LSB", "AM", "FM", "PHONE"]
            case .digital: ["FT8", "FT4", "RTTY", "PSK", "PSK31", "JS8", "DATA", "DIGI", "MFSK"]
            }
        }
    }

    /// Dim spots faster than this many WPM (dim in BOTH lenses). nil = off.
    var wpmCeiling: Int?
    /// Hide (Heard) / dim (Scope) stations already worked today.
    var suppressWorkedToday = false
    /// The main volume valve — skimmer-only spots.
    var rbnEnabled = true
    /// Enabled mode groups; nil/empty = all modes pass.
    var modeGroups: [ModeGroup]?

    var isFiltering: Bool {
        wpmCeiling != nil || suppressWorkedToday || !rbnEnabled
            || !(modeGroups ?? []).isEmpty
    }

    var ffiToggles: FfiQuickToggles {
        FfiQuickToggles(
            wpmCeiling: wpmCeiling.map { UInt32(clamping: $0) },
            suppressWorkedToday: suppressWorkedToday,
            rbnEnabled: rbnEnabled,
            enabledModes: (modeGroups ?? []).flatMap(\.modes)
        )
    }
}
