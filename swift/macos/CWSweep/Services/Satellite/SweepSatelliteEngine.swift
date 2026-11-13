import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - SweepSatelliteEngine

/// CW Sweep's handle on the shared Rust satellite engine (`SatelliteApi`
/// over the cw-store `FieldStore`): SGP4 propagation, SatNOGS/AMSAT
/// cache-through refresh and pass prediction — the same engine iOS and
/// Android run. One lazily-built API behind an actor, like iOS's
/// `SatelliteEngine`. Sync FFI calls block the calling thread, so callers
/// hop off the main actor for them.
nonisolated enum SweepSatelliteEngine {
    // MARK: Internal

    static let activitiesBaseURL = "https://activities.carrierwave.app"

    static func api() async throws -> SatelliteApi {
        if let api = await Holder.shared.api {
            return api
        }
        let store = try await CwStoreProvider.shared.store()
        let api = try SatelliteApi(store: store, activitiesBaseUrl: activitiesBaseURL)
        await Holder.shared.set(api)
        return api
    }

    // MARK: Private

    private actor Holder {
        static let shared = Holder()

        private(set) var api: SatelliteApi?

        func set(_ api: SatelliteApi) {
            self.api = api
        }
    }
}
