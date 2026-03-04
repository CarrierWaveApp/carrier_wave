import CarrierWaveData
import Foundation

extension SessionSpot {
    /// SpotRegion enum accessor
    var spotRegion: SpotRegion {
        SpotRegion(rawValue: region) ?? .other
    }

    /// Create from an EnrichedSpot
    static func from(
        _ enriched: EnrichedSpot,
        loggingSessionId: UUID
    ) -> SessionSpot {
        let spot = enriched.spot
        let sourceString = spot.id.hasPrefix("pota") ? "pota" : "rbn"
        return SessionSpot(
            loggingSessionId: loggingSessionId,
            callsign: spot.callsign,
            frequencyKHz: spot.frequencyKHz,
            mode: spot.mode,
            timestamp: spot.timestamp,
            source: sourceString,
            snr: spot.snr,
            wpm: spot.wpm,
            spotter: spot.spotter,
            spotterGrid: spot.spotterGrid,
            parkRef: spot.parkRef,
            parkName: spot.parkName,
            comments: spot.comments,
            region: enriched.region.rawValue,
            distanceMeters: enriched.distanceMeters
        )
    }
}
