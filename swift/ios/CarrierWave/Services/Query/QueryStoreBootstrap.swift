// Query Store Bootstrap
//
// Single shared bring-up site for the GRDB `QueryStore` so the operator
// profile cache and the experimental Query Runner don't double-register
// (and double-create) the underlying SQLite file.

import CarrierWaveData
import Foundation
import OSLog

@MainActor
enum QueryStoreBootstrap {
    // MARK: Internal

    /// Returns the registered store, creating + registering one if needed.
    /// Returns `nil` if SQLite init fails (e.g. on-disk I/O problem).
    static func ensureStore() -> QueryStore? {
        if let existing = QueryFacade.current {
            return existing
        }
        guard let store = makeStore() else {
            return nil
        }
        QueryFacade.register(store)
        return store
    }

    // MARK: Private

    private static func makeStore() -> QueryStore? {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("CarrierWave", isDirectory: true)
            let dbURL = appSupport.appendingPathComponent("query.sqlite")
            let cacheDir = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("CarrierWave", isDirectory: true)
            let scopeURL = cacheDir.appendingPathComponent("scope.sqlite")
            return try QueryStore(databaseURL: dbURL, scopeURL: scopeURL)
        } catch {
            Logger(subsystem: "com.jsvana.CarrierWave", category: "QueryStoreBootstrap")
                .error("makeStore failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
