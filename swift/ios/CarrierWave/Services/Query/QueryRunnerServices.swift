import CarrierWaveData
import OSLog
import UIKit

// MARK: - QueryRunnerServices

/// Deep-link entry point for `.cwquery` imports. Query *execution* moved
/// to the Rust spot engine (`SpotQueryEditorModel` / `BandScopeQueryRunner`);
/// this shim survives so a `cwquery://` link can drop a saved query into
/// the shared store even if the editor has never been opened — the user
/// finds it waiting next time they visit.
@MainActor
final class QueryRunnerServices {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = QueryRunnerServices()

    /// Import a `cwquery://` URL into the on-disk SavedQueryStore.
    func importSharedURL(_ url: URL) async {
        let store = SavedQueryStores.makeStore()
        do {
            let query = try SavedQueryURL.decode(url)
            _ = try await store.importQuery(query)
        } catch {
            Logger(subsystem: "com.jsvana.CarrierWave", category: "QueryRunnerServices")
                .error("import URL failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
