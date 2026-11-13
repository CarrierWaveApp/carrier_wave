// Park Map Provider
//
// Shared access to the Rust park-map core (`ParkMapApi` over the encrypted
// FieldStore) — bbox-scoped pin queries and reference search backing the
// Parks & Summits map. Mirrors `ReferenceData.api()`'s holder pattern.

import CarrierWaveData
import Foundation
import MapKit

// MARK: - ParkMapAccess

nonisolated enum ParkMapAccess {
    // MARK: Internal

    /// The shared `ParkMapApi` over the app's FieldStore + activities base URL.
    static func api() async throws -> ParkMapApi {
        if let api = await Holder.shared.api {
            return api
        }
        let store = try await CwStoreProvider.shared.store()
        let baseURL = ActivitiesClient.normalizeBase(ActivitiesClient.resolvedBaseURL)
        let api = try ParkMapApi(store: store, baseUrl: baseURL)
        await Holder.shared.set(api)
        return api
    }

    // MARK: Private

    private actor Holder {
        static let shared = Holder()

        private(set) var api: ParkMapApi?

        func set(_ api: ParkMapApi) {
            self.api = api
        }
    }
}

// MARK: - FfiBoundingBox + MapKit

extension FfiBoundingBox {
    /// Build a bounding box from an `MKCoordinateRegion`'s viewport.
    init(mapRegion region: MKCoordinateRegion) {
        self.init(
            west: region.center.longitude - region.span.longitudeDelta / 2,
            south: region.center.latitude - region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2,
            north: region.center.latitude + region.span.latitudeDelta / 2
        )
    }
}
