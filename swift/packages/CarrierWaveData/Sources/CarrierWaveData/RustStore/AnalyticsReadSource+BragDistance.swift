import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + brag distance stats

/// Distance-shaped brag-sheet stats (furthest contacts, per-band, average, lowest power, best
/// watts-per-mile), served from cw-store's `brag_distance_stats`. `query` is the optional
/// `.cwquery` DSL filter (the caller encodes the brag period as a date window).
public extension RustAnalyticsReadSource {
    func bragDistanceStats(query: String, start: Int? = nil, end: Int? = nil) async throws -> BragDistanceStatsResult {
        let stats = try store.bragDistanceStats(query: query, start: start.map(Int64.init), end: end.map(Int64.init))
        return BragDistanceStatsResult(
            furthest: stats.furthest.map(Self.contact),
            furthestQRP: stats.furthestQrp.map(Self.contact),
            furthestCW: stats.furthestCw.map(Self.contact),
            furthestCWQRP: stats.furthestCwQrp.map(Self.contact),
            furthestPerfectRST: stats.furthestPerfectRst.map(Self.contact),
            furthestPerBand: stats.furthestPerBand.map { band in
                BragBandRecordRow(band: band.band, callsign: band.callsign, distanceKm: band.distanceKm)
            },
            averageKm: stats.averageKm,
            lowestPower: stats.lowestPower.map { low in
                BragPowerContactRow(
                    watts: Int(low.watts),
                    callsign: low.callsign,
                    band: low.band,
                    distanceKm: low.distanceKm
                )
            },
            bestWattsPerMile: stats.bestWattsPerMile.map { best in
                BragEfficiencyRow(
                    watts: Int(best.watts),
                    callsign: best.callsign,
                    band: best.band,
                    distanceKm: best.distanceKm
                )
            }
        )
    }

    private static func contact(_ ffi: FfiBragContact) -> BragContactRow {
        BragContactRow(callsign: ffi.callsign, band: ffi.band, distanceKm: ffi.distanceKm)
    }
}
