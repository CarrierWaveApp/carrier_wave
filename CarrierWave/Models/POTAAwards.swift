// POTA Activator Awards
//
// Award tier definitions for POTA activator awards.
// Based on POTA award program rules.

import Foundation

// MARK: - POTAAwardCategory

enum POTAAwardCategory: String, CaseIterable, Sendable {
    case uniqueParks
    case dxEntities
    case workedAllStates
    case rover
    case repeatOffender
    case parkToPark
    case kilo
    case laPorta
    case sixPack
}

// MARK: - POTAAwardTier

struct POTAAwardTier: Sendable, Identifiable {
    // MARK: Lifecycle

    init(
        category: POTAAwardCategory,
        label: String,
        threshold: Int,
        isBinary: Bool = false,
        isRepeatable: Bool = false
    ) {
        id = "\(category.rawValue)-\(threshold)"
        self.category = category
        self.label = label
        self.threshold = threshold
        self.isBinary = isBinary
        self.isRepeatable = isRepeatable
    }

    // MARK: Internal

    let id: String
    let category: POTAAwardCategory
    let label: String
    let threshold: Int
    let isBinary: Bool
    let isRepeatable: Bool
}

// MARK: - POTARules

enum POTARules {
    /// Minimum QSOs required for a valid POTA activation.
    static let activationMinQSOs = 10

    // MARK: - Rover Tiers

    /// Warthog(5), Cheetah(10), Gazelle(15), Mustang(20), Falcon(25), Lion(30). Repeatable.
    static let roverTiers: [POTAAwardTier] = [
        POTAAwardTier(
            category: .rover, label: "Warthog", threshold: 5, isRepeatable: true
        ),
        POTAAwardTier(
            category: .rover, label: "Cheetah", threshold: 10, isRepeatable: true
        ),
        POTAAwardTier(
            category: .rover, label: "Gazelle", threshold: 15, isRepeatable: true
        ),
        POTAAwardTier(
            category: .rover, label: "Mustang", threshold: 20, isRepeatable: true
        ),
        POTAAwardTier(
            category: .rover, label: "Falcon", threshold: 25, isRepeatable: true
        ),
        POTAAwardTier(
            category: .rover, label: "Lion", threshold: 30, isRepeatable: true
        ),
    ]

    // MARK: - Kilo (binary per park)

    static let kiloTier = POTAAwardTier(
        category: .kilo, label: "Kilo", threshold: 1_000, isBinary: true
    )

    // MARK: - LaPorta N1CC (binary)

    static let laPortaTier = POTAAwardTier(
        category: .laPorta, label: "LaPorta N1CC", threshold: 1, isBinary: true
    )

    // MARK: - Six Pack (binary)

    static let sixPackTier = POTAAwardTier(
        category: .sixPack, label: "Six Pack", threshold: 1, isBinary: true
    )

    // MARK: - Worked All States (binary)

    static let workedAllStatesTier = POTAAwardTier(
        category: .workedAllStates,
        label: "Activator WAS",
        threshold: 50,
        isBinary: true
    )

    // MARK: - Unique Parks Tiers

    /// Named tiers: Bronze(10)..Sapphire(75), then Arizona Agave(100)..Tasmanian Devil(20000)
    static func uniqueParksTiers(upTo count: Int = 0) -> [POTAAwardTier] {
        var tiers: [POTAAwardTier] = [
            POTAAwardTier(category: .uniqueParks, label: "Bronze", threshold: 10),
            POTAAwardTier(category: .uniqueParks, label: "Silver", threshold: 15),
            POTAAwardTier(category: .uniqueParks, label: "Gold", threshold: 25),
            POTAAwardTier(category: .uniqueParks, label: "Platinum", threshold: 50),
            POTAAwardTier(category: .uniqueParks, label: "Sapphire", threshold: 75),
            POTAAwardTier(category: .uniqueParks, label: "Arizona Agave", threshold: 100),
            POTAAwardTier(category: .uniqueParks, label: "Carolina Reaper", threshold: 150),
            POTAAwardTier(category: .uniqueParks, label: "Diamond", threshold: 200),
            POTAAwardTier(category: .uniqueParks, label: "Emerald", threshold: 300),
            POTAAwardTier(category: .uniqueParks, label: "Fantasy", threshold: 400),
            POTAAwardTier(category: .uniqueParks, label: "Giant Panda", threshold: 500),
            POTAAwardTier(category: .uniqueParks, label: "Hornbill", threshold: 750),
            POTAAwardTier(category: .uniqueParks, label: "Iron Horse", threshold: 1_000),
            POTAAwardTier(category: .uniqueParks, label: "Jade", threshold: 1_500),
            POTAAwardTier(category: .uniqueParks, label: "Komodo", threshold: 2_000),
            POTAAwardTier(category: .uniqueParks, label: "Lemur", threshold: 3_000),
            POTAAwardTier(category: .uniqueParks, label: "Mastodon", threshold: 4_000),
            POTAAwardTier(category: .uniqueParks, label: "Narwhal", threshold: 5_000),
            POTAAwardTier(category: .uniqueParks, label: "Osprey", threshold: 7_500),
            POTAAwardTier(category: .uniqueParks, label: "Phoenix", threshold: 10_000),
            POTAAwardTier(category: .uniqueParks, label: "Quetzal", threshold: 12_500),
            POTAAwardTier(category: .uniqueParks, label: "Rhino", threshold: 15_000),
            POTAAwardTier(category: .uniqueParks, label: "Sasquatch", threshold: 17_500),
            POTAAwardTier(category: .uniqueParks, label: "Tasmanian Devil", threshold: 20_000),
        ]
        // Extend beyond 20k if needed
        if count > 20_000 {
            var threshold = 25_000
            while threshold <= count + 5_000 {
                tiers.append(POTAAwardTier(
                    category: .uniqueParks,
                    label: "\(threshold) Parks",
                    threshold: threshold
                ))
                threshold += 5_000
            }
        }
        return tiers
    }

    // MARK: - DX Entities Tiers

    /// Increments of 5 entities activated from.
    static func dxEntitiesTiers(upTo count: Int = 0) -> [POTAAwardTier] {
        var tiers: [POTAAwardTier] = []
        var threshold = 5
        while threshold <= max(count + 5, 25) {
            tiers.append(POTAAwardTier(
                category: .dxEntities,
                label: "\(threshold) DX Entities",
                threshold: threshold
            ))
            threshold += 5
        }
        return tiers
    }

    // MARK: - Repeat Offender Tiers

    /// Oasis(20), Homestead(30), Haven(40), Sanctuary(50), Fortress(60),
    /// Citadel(70), Stronghold(80), Castle(90), Eagle's Nest(100), then +20.
    static func repeatOffenderTiers(upTo count: Int = 0) -> [POTAAwardTier] {
        var tiers: [POTAAwardTier] = [
            POTAAwardTier(category: .repeatOffender, label: "Oasis", threshold: 20),
            POTAAwardTier(category: .repeatOffender, label: "Homestead", threshold: 30),
            POTAAwardTier(category: .repeatOffender, label: "Haven", threshold: 40),
            POTAAwardTier(category: .repeatOffender, label: "Sanctuary", threshold: 50),
            POTAAwardTier(category: .repeatOffender, label: "Fortress", threshold: 60),
            POTAAwardTier(category: .repeatOffender, label: "Citadel", threshold: 70),
            POTAAwardTier(category: .repeatOffender, label: "Stronghold", threshold: 80),
            POTAAwardTier(category: .repeatOffender, label: "Castle", threshold: 90),
            POTAAwardTier(category: .repeatOffender, label: "Eagle's Nest", threshold: 100),
        ]
        if count > 100 {
            var threshold = 120
            while threshold <= count + 20 {
                tiers.append(POTAAwardTier(
                    category: .repeatOffender,
                    label: "\(threshold) Activations",
                    threshold: threshold
                ))
                threshold += 20
            }
        }
        return tiers
    }

    // MARK: - Park to Park Tiers

    /// Increments of 50 P2P QSOs.
    static func parkToParkTiers(upTo count: Int = 0) -> [POTAAwardTier] {
        var tiers: [POTAAwardTier] = []
        var threshold = 50
        while threshold <= max(count + 50, 250) {
            tiers.append(POTAAwardTier(
                category: .parkToPark,
                label: "\(threshold) P2P QSOs",
                threshold: threshold
            ))
            threshold += 50
        }
        return tiers
    }

    // MARK: - Tier Lookup

    static func progress(
        for count: Int,
        category: POTAAwardCategory
    ) -> (current: POTAAwardTier?, next: POTAAwardTier?) {
        let tiers = allTiers(for: category, upTo: count)
        let achieved = tiers.last { $0.threshold <= count }
        let next = tiers.first { $0.threshold > count }
        return (current: achieved, next: next)
    }

    static func allTiers(
        for category: POTAAwardCategory,
        upTo count: Int = 0
    ) -> [POTAAwardTier] {
        switch category {
        case .uniqueParks:
            uniqueParksTiers(upTo: count)
        case .dxEntities:
            dxEntitiesTiers(upTo: count)
        case .workedAllStates:
            [workedAllStatesTier]
        case .rover:
            roverTiers
        case .repeatOffender:
            repeatOffenderTiers(upTo: count)
        case .parkToPark:
            parkToParkTiers(upTo: count)
        case .kilo:
            [kiloTier]
        case .laPorta:
            [laPortaTier]
        case .sixPack:
            [sixPackTier]
        }
    }
}
