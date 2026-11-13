// Satellite Engine
//
// Shared access to the Rust satellite core (`SatelliteApi` over the encrypted
// FieldStore): SGP4 propagation, SatNOGS/AMSAT cache-through refresh, pass
// prediction, mutual planning, and alert planning — the same engine Android
// runs. Modeled on `EquipmentProvider`: one lazily-built API held behind an
// actor. Sync FFI calls (positions/groundTrack/catalog) block the calling
// thread, so callers hop off the main actor for them.

import CarrierWaveCore
import CarrierWaveData
import UIKit

nonisolated enum SatelliteEngine {
    // MARK: Internal

    /// The shared `SatelliteApi` over the app's FieldStore.
    static func api() async throws -> SatelliteApi {
        if let api = await Holder.shared.api {
            return api
        }
        let store = try await CwStoreProvider.shared.store()
        let base = ActivitiesClient.normalizeBase(ActivitiesClient.resolvedBaseURL)
        let api = try SatelliteApi(store: store, activitiesBaseUrl: base)
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
