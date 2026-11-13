import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + brag geographic

/// Geographic-reach brag-sheet stats (DXCC entities, new-this-period, states, grid squares,
/// continents, most-continents-in-a-day, WAS progress), served from cw-store's
/// `brag_geographic`. `query` is the optional `.cwquery` DSL filter (the brag period).
public extension RustAnalyticsReadSource {
    func bragGeographic(query: String, start: Int? = nil, end: Int? = nil) async throws -> BragGeographicResult {
        let geo = try store.bragGeographic(query: query, start: start.map(Int64.init), end: end.map(Int64.init))
        return BragGeographicResult(
            dxccEntities: Int(geo.dxccEntities),
            newDXCCEntities: Int(geo.newDxccEntities),
            statesProvinces: Int(geo.statesProvinces),
            gridSquares: Int(geo.gridSquares),
            continents: Int(geo.continents),
            mostContinentsDay: Int(geo.mostContinentsDay),
            wasStates: Int(geo.wasStates)
        )
    }
}
