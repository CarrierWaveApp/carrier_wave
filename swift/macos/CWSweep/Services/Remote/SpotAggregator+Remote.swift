import CarrierWaveCore
import Foundation

// MARK: - SpotAggregator → RemoteSpot bridging

//
// Converts the local enriched spot model to the wire format and applies the
// optional client-side filters. Lives on the macOS app side because RemoteSpot
// is intentionally lighter than EnrichedSpot.

extension SpotAggregator {
    /// Returns the current spot list converted to wire-format `RemoteSpot`s,
    /// honoring any band/mode/source filters supplied by the client.
    @MainActor
    func remoteSpots(filter: SubscribeFilter?) -> [RemoteSpot] {
        spots.compactMap { enriched in
            Self.makeRemoteSpot(from: enriched, filter: filter)
        }
    }

    /// Convert a single enriched spot, returning nil if it fails the filter.
    @MainActor
    static func makeRemoteSpot(
        from enriched: EnrichedSpot,
        filter: SubscribeFilter?
    ) -> RemoteSpot? {
        let unified = enriched.spot
        let band = BandUtilities.deriveBand(from: unified.frequencyKHz)
        guard passesFilter(enriched: enriched, band: band, filter: filter) else {
            return nil
        }

        return RemoteSpot(
            id: unified.id,
            callsign: unified.callsign,
            freqHz: UInt64((unified.frequencyKHz * 1_000).rounded()),
            mode: unified.mode.isEmpty ? nil : unified.mode,
            band: band,
            source: unified.source.rawValue,
            spotter: unified.spotter,
            comment: unified.comments ?? unified.splitInfo,
            snr: unified.snr,
            dxccEntity: enriched.dxccEntity,
            dxccPrefix: unified.dxccPrefix,
            region: enriched.region.rawValue,
            needed: isNeeded(enriched.neededStatus),
            workedBefore: false,
            spottedAt: unified.timestamp,
            distanceMeters: enriched.distanceMeters,
            bearingDegrees: enriched.bearingDegrees
        )
    }

    @MainActor
    private static func passesFilter(
        enriched: EnrichedSpot,
        band: String?,
        filter: SubscribeFilter?
    ) -> Bool {
        guard let filter else {
            return true
        }
        let unified = enriched.spot
        if let bands = filter.bands, !bands.isEmpty, let band, !bands.contains(band) {
            return false
        }
        if let modes = filter.modes, !modes.isEmpty, !modes.contains(unified.mode) {
            return false
        }
        if let sources = filter.sources, !sources.isEmpty,
           !sources.contains(unified.source.rawValue)
        {
            return false
        }
        if let minSNR = filter.minSNR, let snr = unified.snr, snr < minSNR {
            return false
        }
        if filter.neededOnly == true, !isNeeded(enriched.neededStatus) {
            return false
        }
        return true
    }

    private static func isNeeded(_ status: NeededStatus) -> Bool {
        switch status {
        case .newEntity,
             .newBandSlot:
            true
        case .workedNotConfirmed,
             .confirmed,
             .unknown:
            false
        }
    }
}
