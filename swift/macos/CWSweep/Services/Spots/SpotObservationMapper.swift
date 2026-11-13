import CarrierWaveCore
import CarrierWaveData
import Foundation

enum SpotObservationMapper {
    static func observationRow(
        from spot: UnifiedSpot,
        priority: Int,
        dxEntity: DXCCEntity? = nil
    ) -> SpotObservationRow {
        // Resolve coords for the *spotted* (DX) callsign — what the
        // user means when they say "where is this spot." Grid centre
        // wins when known (DXHeat / DXWatch / call-info enrichment
        // populate `dxGrid`); otherwise we fall back to the DXCC
        // entity centroid for the spotted callsign — country-level,
        // but free and synchronous. Persisted on the row so distance
        // queries don't have to JOIN through anything.
        let coords: (lat: Double, lon: Double)? = {
            if let grid = spot.dxGrid,
               let coord = MaidenheadConverter.coordinate(from: grid)
            {
                return (coord.latitude, coord.longitude)
            }
            if let lat = dxEntity?.latitude,
               let lon = dxEntity?.longitude
            {
                return (lat, lon)
            }
            return nil
        }()
        return SpotObservationRow(
            obsId: UUID().uuidString,
            spotId: spot.id,
            callsign: spot.callsign.uppercased(),
            band: spot.band,
            mode: spot.mode,
            freqHz: Int64((spot.frequencyKHz * 1_000.0).rounded()),
            source: spot.source.rawValue,
            spotter: spot.spotter,
            spotLat: coords?.lat,
            spotLon: coords?.lon,
            snrDb: spot.snr,
            speedWpm: spot.wpm,
            comment: spot.comments,
            receivedAt: spot.timestamp,
            priority: priority
        )
    }

    /// Build a SpotterRow with as much location detail as is available
    /// synchronously. The caller supplies the spotter's DXCC entity (via
    /// CTY prefix lookup); this gives us a country-centroid lat/lon and
    /// a continent for free, with no network round-trip. Higher-precision
    /// grid/lat/lon should be filled by an async HamDB pass afterwards.
    static func spotterRow(
        from spot: UnifiedSpot,
        spotterEntity: DXCCEntity? = nil
    ) -> SpotterRow? {
        guard let spotter = spot.spotter, !spotter.isEmpty else {
            return nil
        }
        return SpotterRow(
            callsign: spotter.uppercased(),
            grid: spot.spotterGrid,
            lat: spotterEntity?.latitude,
            lon: spotterEntity?.longitude,
            dxccEntity: spotterEntity?.name,
            continent: spotterEntity?.continent,
            isSkimmer: spot.source == .rbn
        )
    }
}
