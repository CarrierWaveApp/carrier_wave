import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + brag POTA

/// POTA-category brag-sheet stats (parks activated / hunted, park-to-park, best activation,
/// new-this-period parks), served from cw-store's `brag_pota`. `query` is the optional
/// `.cwquery` DSL filter (the brag period).
public extension RustAnalyticsReadSource {
    func bragPota(query: String, start: Int? = nil, end: Int? = nil) async throws -> BragPotaResult {
        let pota = try store.bragPota(query: query, start: start.map(Int64.init), end: end.map(Int64.init))
        return BragPotaResult(
            parksActivated: Int(pota.parksActivated),
            parksHunted: Int(pota.parksHunted),
            parkToPark: Int(pota.parkToPark),
            bestActivation: pota.bestActivation.map {
                BragBestActivationRow(park: $0.park, day: $0.day, count: Int($0.count))
            },
            newParks: Int(pota.newParks)
        )
    }
}
