// POTA Awards Computation
//
// Pure computation logic for POTA activator awards progress.
// No SwiftData dependency - works with POTAActivation arrays.

import CarrierWaveData
import Foundation

// MARK: - POTAAwardsProgress

struct POTAAwardsProgress: Sendable {
    let uniqueParksCount: Int
    let dxEntitiesCount: Int
    let statesActivated: Set<String>
    let roverMaxParks: Int
    let repeatOffenderMaxCount: Int
    let parkToParkCount: Int
    let kiloParks: [String]
    let laPortaEarned: Bool
    let sixPackEarned: Bool
}

// MARK: - POTAAwardsComputation

enum POTAAwardsComputation {
    // MARK: Internal

    static func compute(
        from activations: [POTAActivation],
        allParkQSOs: [QSO]
    ) -> POTAAwardsProgress {
        POTAAwardsProgress(
            uniqueParksCount: computeUniqueParks(activations),
            dxEntitiesCount: computeDXEntities(activations),
            statesActivated: computeWorkedAllStates(activations),
            roverMaxParks: computeRover(activations),
            repeatOffenderMaxCount: computeRepeatOffender(activations),
            parkToParkCount: computeParkToPark(allParkQSOs),
            kiloParks: computeKilo(allParkQSOs),
            laPortaEarned: computeLaPorta(activations),
            sixPackEarned: computeSixPack(activations)
        )
    }

    // MARK: Private

    // MARK: - Unique Parks

    /// Parks with 10+ QSOs (valid activations), splitting two-fers
    private static func computeUniqueParks(
        _ activations: [POTAActivation]
    ) -> Int {
        var parkSet = Set<String>()
        for activation in activations
            where activation.qsoCount >= POTARules.activationMinQSOs
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
        for activation in activations where activation.qsoCount >= POTARules.activationMinQSOs {
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
            where activation.qsoCount >= POTARules.activationMinQSOs
        {
            let parks = POTAClient.splitParkReferences(
                activation.parkReference
            )
            for park in parks {
                if let state = stateForPark(
                    park, activation: activation, cache: cache
                ) {
                    states.insert(state)
                }
            }
        }
        return states
    }

    /// Resolve US state for a park: cache lookup, then grid fallback
    private static func stateForPark(
        _ parkRef: String,
        activation: POTAActivation,
        cache: POTAParksCache
    ) -> String? {
        // Try parks cache first (has locationDesc like "US-WY")
        if let park = cache.parkSync(for: parkRef),
           let state = park.state,
           park.countryPrefix == "US" || park.countryPrefix == "K"
        {
            return state
        }

        // Fall back to grid square from QSO data
        let parkPrefix = String(
            parkRef.split(separator: "-").first ?? ""
        )
        guard parkPrefix == "US" || parkPrefix == "K" else {
            return nil
        }
        if let grid = activation.qsos.first?.myGrid {
            return POTAClient.gridToUSState(grid)
        }
        return nil
    }

    // MARK: - Rover

    /// Max unique parks activated in a single UTC day
    private static func computeRover(
        _ activations: [POTAActivation]
    ) -> Int {
        // Group valid activations by UTC date
        var parksByDate: [String: Set<String>] = [:]
        for activation in activations where activation.qsoCount >= POTARules.activationMinQSOs {
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
        for activation in activations where activation.qsoCount >= POTARules.activationMinQSOs {
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

    /// Parks with 1000+ QSOs (regardless of activation validity)
    private static func computeKilo(_ allParkQSOs: [QSO]) -> [String] {
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
        return countByPark.filter { $0.value >= 1_000 }
            .keys.sorted()
    }

    // MARK: - LaPorta N1CC

    /// 10 parks x 10 bands from valid activations
    private static func computeLaPorta(
        _ activations: [POTAActivation]
    ) -> Bool {
        var parkBandPairs = Set<String>()
        var uniqueParks = Set<String>()
        var uniqueBands = Set<String>()
        for activation in activations where activation.qsoCount >= POTARules.activationMinQSOs {
            let parks = POTAClient.splitParkReferences(
                activation.parkReference
            )
            for park in parks {
                let normalizedPark = park.uppercased()
                for qso in activation.qsos {
                    let band = qso.band
                    let key = "\(normalizedPark)|\(band)"
                    parkBandPairs.insert(key)
                    uniqueParks.insert(normalizedPark)
                    uniqueBands.insert(band)
                }
            }
        }
        return uniqueParks.count >= 10 && uniqueBands.count >= 10
    }

    // MARK: - Six Pack

    /// 10 QSOs on 6m from 6 different parks (valid activations)
    private static func computeSixPack(
        _ activations: [POTAActivation]
    ) -> Bool {
        var parksWithTenOn6m = Set<String>()
        for activation in activations where activation.qsoCount >= POTARules.activationMinQSOs {
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
