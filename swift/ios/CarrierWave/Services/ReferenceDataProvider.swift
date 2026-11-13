// Reference Data Provider
//
// Shared access to the Rust reference-data core (`ReferenceDataApi` over the
// encrypted FieldStore) — the External Data downloads: POTA parks, SOTA
// summits, WWFF directory, equipment catalog, FCC callsigns, and SOTA
// activation zones. Download, parse, and storage live in the core; the
// Swift caches keep only their in-memory query surfaces.

import CarrierWaveData
import UIKit

nonisolated enum ReferenceData {
    // MARK: Internal

    /// Page size for hydrating Swift in-memory caches from the store
    /// (matches the core's bounded-fetch limit).
    static let pageSize: Int64 = 1_000

    /// Directory holding the FCC SQLite — the same ApplicationSupport/FCC
    /// location the Swift `FCCLookupService` downloaded into, so an existing
    /// database is reused instead of re-downloaded.
    static var fccDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return appSupport.appendingPathComponent("FCC", isDirectory: true)
    }

    /// The shared `ReferenceDataApi` over the app's FieldStore + activities
    /// base URL.
    static func api() async throws -> ReferenceDataApi {
        if let api = await Holder.shared.api {
            return api
        }
        let store = try await CwStoreProvider.shared.store()
        let baseURL = ActivitiesClient.normalizeBase(ActivitiesClient.resolvedBaseURL)
        let api = try ReferenceDataApi(
            store: store,
            baseUrl: baseURL,
            dataDir: fccDirectory.path
        )
        await Holder.shared.set(api)
        return api
    }

    // MARK: Private

    private actor Holder {
        static let shared = Holder()

        private(set) var api: ReferenceDataApi?

        func set(_ api: ReferenceDataApi) {
            self.api = api
        }
    }
}
