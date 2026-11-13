import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + POTA awards / WAS250

/// POTA activator awards + America 250 WAS, served from cw-store's `pota_awards`
/// and `was250` aggregates. Split from `AnalyticsReadSource.swift` for type-body
/// length. The `query` is the optional `.cwquery` DSL filter (empty = all).
public extension RustAnalyticsReadSource {
    func potaAwards(query: String) async throws -> POTAAwardsResult {
        let awards = try store.potaAwards(query: query)
        return POTAAwardsResult(
            uniqueParksCount: Int(awards.uniqueParksCount),
            dxEntitiesCount: Int(awards.dxEntitiesCount),
            statesActivated: awards.statesActivated,
            roverMaxParks: Int(awards.roverMaxParks),
            repeatOffenderMaxCount: Int(awards.repeatOffenderMaxCount),
            parkToParkCount: Int(awards.parkToParkCount),
            kiloParks: awards.kiloParks,
            nearKiloParks: awards.nearKiloParks.map {
                NearKiloParkRow(reference: $0.reference, qsoCount: Int($0.qsoCount))
            },
            laPortaEarned: awards.laPortaEarned,
            laPortaQualifyingParks: Int(awards.laPortaQualifyingParks),
            sixPackEarned: awards.sixPackEarned,
            bestSingleParkTotal: Int(awards.bestSingleParkTotal),
            totalParkQSOs: Int(awards.totalParkQsos),
            metadataExcluded: Int(awards.metadataExcluded),
            totalActivationGroups: Int(awards.totalActivationGroups),
            validActivationGroups: Int(awards.validActivationGroups)
        )
    }

    func was250(query: String) async throws -> WAS250Result {
        let was = try store.was250(query: query)
        return WAS250Result(
            statesWorked: was.statesWorked,
            cwStates: was.cwStates,
            phoneStates: was.phoneStates,
            digitalStates: was.digitalStates,
            totalQSOs: Int(was.totalQsos),
            metadataExcluded: Int(was.metadataExcluded),
            withStateField: Int(was.withStateField),
            withValidState: Int(was.withValidState)
        )
    }
}
