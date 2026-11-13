import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - SdrApiProvider

/// Shared `SdrApi` instance (Rust core). Owns the KiwiSDR directory cache,
/// `/status` enrichment, Tune-In candidate selection, the websocket audio
/// client, and the QSY / receiver-quality monitors.
nonisolated enum SdrApiProvider {
    // MARK: Internal

    /// The shared API, created lazily. Thread-safe.
    static func shared() throws -> SdrApi {
        try lock.withLock {
            if let cached {
                return cached
            }
            let cachePath = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("kiwisdr_directory.json")
                .path
            let api = try SdrApi(
                activitiesBaseUrl: ActivitiesClient.normalizeBase(
                    ActivitiesClient.resolvedBaseURL
                ),
                directoryCachePath: cachePath
            )
            cached = api
            return api
        }
    }

    // MARK: Private

    private static let lock = NSLock()

    /// Single reference guarded by `lock` (sanctioned NSLock pattern).
    nonisolated(unsafe) private static var cached: SdrApi?
}
