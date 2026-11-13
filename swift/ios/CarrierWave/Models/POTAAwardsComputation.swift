// POTA Awards Computation
//
// Pure computation logic for POTA activator awards progress.
// No SwiftData dependency - works with POTAActivation arrays.

import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - POTAAwardsProgress

struct POTAAwardsProgress {
    let uniqueParksCount: Int
    let dxEntitiesCount: Int
    let statesActivated: Set<String>
    let roverMaxParks: Int
    let repeatOffenderMaxCount: Int
    let parkToParkCount: Int
    let kiloParks: [String]
    let nearKiloParks: [NearKiloPark]
    let laPortaEarned: Bool
    let laPortaQualifyingParks: Int
    let sixPackEarned: Bool
    /// Highest total QSO count at any single park (across all activations)
    let bestSingleParkTotal: Int

    // Filter pipeline intermediate counts
    let totalParkQSOs: Int
    let metadataExcluded: Int
    let totalActivationGroups: Int
    let validActivationGroups: Int
}

// MARK: - NearKiloPark

/// A park approaching the 1,000-QSO kilo threshold.
struct NearKiloPark: Identifiable {
    let reference: String
    let qsoCount: Int

    var id: String {
        reference
    }

    var remaining: Int {
        max(1_000 - qsoCount, 0)
    }
}

// MARK: - POTAAwardsComputation

enum POTAAwardsComputation {
    // MARK: Internal

    static func compute(
        from activations: [POTAActivation],
        allParkQSOs: [QSO]
    ) -> POTAAwardsProgress {
        let parkQSOCounts = computeParkQSOCounts(allParkQSOs)
        let laPortaCount = computeLaPortaCount(activations)
        let metadataCount = allParkQSOs.filter {
            QSOMode.isMetadata($0.mode)
        }.count
        let validActivations = activations.filter {
            $0.uniqueQSOCount >= POTARules.activationMinQSOs
        }
        return POTAAwardsProgress(
            uniqueParksCount: computeUniqueParks(activations),
            dxEntitiesCount: computeDXEntities(activations),
            statesActivated: computeWorkedAllStates(activations),
            roverMaxParks: computeRover(activations),
            repeatOffenderMaxCount: computeRepeatOffender(activations),
            parkToParkCount: computeParkToPark(allParkQSOs),
            kiloParks: kiloParks(from: parkQSOCounts),
            nearKiloParks: nearKiloParks(from: parkQSOCounts),
            laPortaEarned: laPortaCount >= 10,
            laPortaQualifyingParks: laPortaCount,
            sixPackEarned: computeSixPack(activations),
            bestSingleParkTotal: parkQSOCounts.values.max() ?? 0,
            totalParkQSOs: allParkQSOs.count,
            metadataExcluded: metadataCount,
            totalActivationGroups: activations.count,
            validActivationGroups: validActivations.count
        )
    }

    // MARK: Private

    private static let nearKiloThreshold = 100

    // MARK: - Unique Parks

    /// Parks with 10+ QSOs (valid activations), splitting two-fers
    private static func computeUniqueParks(
        _ activations: [POTAActivation]
    ) -> Int {
        var parkSet = Set<String>()
        for activation in activations
            where activation.uniqueQSOCount >= POTARules.activationMinQSOs
        {
            let individualParks = POTAClient.splitParkReferences(
                activation.parkReference
            )
            for park in individualParks {
                parkSet.insert(park.uppercased())
            }
        }
        return parkSet.count
    }

    // MARK: - DX Entities

    /// Unique DXCC entities activated from (in valid activations)
    private static func computeDXEntities(
        _ activations: [POTAActivation]
    ) -> Int {
        var entities = Set<Int>()
        for activation in activations where activation.uniqueQSOCount >= POTARules.activationMinQSOs {
            for qso in activation.qsos {
                if let dxcc = qso.dxcc, dxcc > 0 {
                    entities.insert(dxcc)
                    break // One entity per activation is enough
                }
            }
        }
        return entities.count
    }

    // MARK: - Worked All States

    /// US states with valid activations. Uses parks cache for state,
    /// falls back to grid square derivation.
    private static func computeWorkedAllStates(
        _ activations: [POTAActivation]
    ) -> Set<String> {
        let cache = POTAParksCache.shared
        var states = Set<String>()
        for activation in activations
            where activation.uniqueQSOCount >= POTARules.activationMinQSOs
        {
            let parks = POTAClient.splitParkReferences(
                activation.parkReference
            )
            for park in parks {
                for state in statesForPark(
                    park, activation: activation, cache: cache
                ) {
                    states.insert(state)
                }
            }
        }
        return states
    }

    /// Resolve US state(s) for a park: cache lookup, then grid fallback.
    /// Returns multiple states for parks spanning state borders.
    private static func statesForPark(
        _ parkRef: String,
        activation: POTAActivation,
        cache: POTAParksCache
    ) -> [String] {
        // Try parks cache first (handles multi-state like "US-WY,US-MT")
        if let park = cache.parkSync(for: parkRef),
           park.countryPrefix == "US" || park.countryPrefix == "K"
        {
            let parkStates = park.states.filter { !$0.isEmpty }
            if !parkStates.isEmpty {
                return parkStates
            }
        }

        // Fall back to grid square from QSO data
        let parkPrefix = String(
            parkRef.split(separator: "-").first ?? ""
        )
        guard parkPrefix == "US" || parkPrefix == "K" else {
            return []
        }
        if let grid = activation.qsos.first?.myGrid,
           let state = POTAClient.gridToUSState(grid)
        {
            return [state]
        }
        return []
    }

    // MARK: - Rover

    /// Max unique parks activated in a single UTC day
    private static func computeRover(
        _ activations: [POTAActivation]
    ) -> Int {
        // Group valid activations by UTC date
        var parksByDate: [String: Set<String>] = [:]
        for activation in activations where activation.uniqueQSOCount >= POTARules.activationMinQSOs {
            let dateKey = activation.utcDateString
            let parks = POTAClient.splitParkReferences(
                activation.parkReference
            )
            for park in parks {
                parksByDate[dateKey, default: []].insert(park.uppercased())
            }
        }
        return parksByDate.values.map(\.count).max() ?? 0
    }

    // MARK: - Repeat Offender

    /// Most activations of a single park (splitting two-fers)
    private static func computeRepeatOffender(
        _ activations: [POTAActivation]
    ) -> Int {
        var countByPark: [String: Int] = [:]
        for activation in activations where activation.uniqueQSOCount >= POTARules.activationMinQSOs {
            let parks = POTAClient.splitParkReferences(
                activation.parkReference
            )
            for park in parks {
                countByPark[park.uppercased(), default: 0] += 1
            }
        }
        return countByPark.values.max() ?? 0
    }

    // MARK: - Park to Park

    /// QSOs where both sides are in a park
    private static func computeParkToPark(_ allParkQSOs: [QSO]) -> Int {
        allParkQSOs.filter { qso in
            guard let myPark = qso.parkReference,
                  !myPark.isEmpty,
                  let theirPark = qso.theirParkReference,
                  !theirPark.isEmpty
            else {
                return false
            }
            return true
        }.count
    }

    // MARK: - Kilo

    /// Count QSOs per park reference (regardless of activation validity).
    private static func computeParkQSOCounts(
        _ allParkQSOs: [QSO]
    ) -> [String: Int] {
        var countByPark: [String: Int] = [:]
        for qso in allParkQSOs {
            guard let parkRef = qso.parkReference, !parkRef.isEmpty else {
                continue
            }
            let parks = POTAClient.splitParkReferences(parkRef)
            for park in parks {
                countByPark[park.uppercased(), default: 0] += 1
            }
        }
        return countByPark
    }

    /// Parks with 1000+ QSOs.
    private static func kiloParks(
        from counts: [String: Int]
    ) -> [String] {
        counts.filter { $0.value >= 1_000 }.keys.sorted()
    }

    /// Parks within 100 QSOs of 1,000 (900–999 range).
    private static func nearKiloParks(
        from counts: [String: Int]
    ) -> [NearKiloPark] {
        let threshold = 1_000 - nearKiloThreshold
        return counts
            .filter { $0.value >= threshold && $0.value < 1_000 }
            .map { NearKiloPark(reference: $0.key, qsoCount: $0.value) }
            .sorted { $0.qsoCount > $1.qsoCount }
    }

    // MARK: - LaPorta N1CC

    /// Count parks with 10+ bands from valid activations (N1CC requires 10).
    private static func computeLaPortaCount(
        _ activations: [POTAActivation]
    ) -> Int {
        var bandsByPark: [String: Set<String>] = [:]
        for activation in activations where activation.uniqueQSOCount >= POTARules.activationMinQSOs {
            let parks = POTAClient.splitParkReferences(
                activation.parkReference
            )
            for park in parks {
                let normalizedPark = park.uppercased()
                for qso in activation.qsos {
                    bandsByPark[
                        normalizedPark, default: []
                    ].insert(qso.band.uppercased())
                }
            }
        }
        return bandsByPark.values.filter { $0.count >= 10 }.count
    }

    // MARK: - Six Pack

    /// 10 QSOs on 6m from 6 different parks (valid activations)
    private static func computeSixPack(
        _ activations: [POTAActivation]
    ) -> Bool {
        var parksWithTenOn6m = Set<String>()
        for activation in activations where activation.uniqueQSOCount >= POTARules.activationMinQSOs {
            let sixMeterQSOs = activation.qsos.filter { $0.band == "6m" }
            if sixMeterQSOs.count >= 10 {
                let parks = POTAClient.splitParkReferences(
                    activation.parkReference
                )
                for park in parks {
                    parksWithTenOn6m.insert(park.uppercased())
                }
            }
        }
        return parksWithTenOn6m.count >= 6
    }
}

// MARK: - WAS250Progress

/// Progress toward the ARRL America 250 WAS award (all 50 states in 2026).
struct WAS250Progress {
    /// States worked on any mode in 2026.
    let statesWorked: Set<String>
    /// States worked on CW in 2026.
    let cwStates: Set<String>
    /// States worked on Phone in 2026.
    let phoneStates: Set<String>
    /// States worked on Digital in 2026.
    let digitalStates: Set<String>

    // Filter pipeline counts
    let totalQSOs2026: Int
    let metadataExcluded: Int
    let withStateField: Int
    let withValidState: Int

    var triplePlayComplete: Bool {
        cwStates.count >= 50
            && phoneStates.count >= 50
            && digitalStates.count >= 50
    }
}

// MARK: - WAS250Computation

enum WAS250Computation {
    // MARK: Internal

    /// Compute WAS 250 progress from all QSOs in 2026.
    static func compute(from qsos: [QSO]) -> WAS250Progress {
        var allStates = Set<String>()
        var cwStates = Set<String>()
        var phoneStates = Set<String>()
        var digitalStates = Set<String>()
        var metadataCount = 0
        var withStateCount = 0
        var validStateCount = 0

        for qso in qsos {
            guard !QSOMode.isMetadata(qso.mode) else {
                metadataCount += 1
                continue
            }
            guard let rawState = qso.state else {
                continue
            }
            withStateCount += 1
            let state = USStates.normalizeAbbreviation(rawState)
            guard validStates.contains(state) else {
                continue
            }
            validStateCount += 1
            allStates.insert(state)

            switch ModeEquivalence.family(for: qso.mode) {
            case .cw:
                cwStates.insert(state)
            case .phone:
                phoneStates.insert(state)
            case .digital:
                digitalStates.insert(state)
            case .other:
                break
            }
        }

        return WAS250Progress(
            statesWorked: allStates,
            cwStates: cwStates,
            phoneStates: phoneStates,
            digitalStates: digitalStates,
            totalQSOs2026: qsos.count,
            metadataExcluded: metadataCount,
            withStateField: withStateCount,
            withValidState: validStateCount
        )
    }

    // MARK: Private

    /// All 50 US state abbreviations for validation.
    private static let validStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE",
        "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS",
        "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS",
        "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY",
        "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV",
        "WI", "WY",
    ]
}
