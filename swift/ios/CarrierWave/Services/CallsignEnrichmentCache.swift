// Callsign Enrichment Cache
//
// Disk-backed local cache of the activities-server enrichment dataset
// (CWops, future SKCC, etc.). The full dataset is small enough (low
// hundreds of KB gzipped) to keep entirely in memory for O(1) lookup,
// and we mirror the same pattern used by SOTASummitsCache /
// WWFFReferencesCache so settings UIs and lookup paths stay consistent.
//
// Lifecycle:
//   1. App launch calls `ensureLoaded()`. If a disk copy exists, it is
//      loaded synchronously into memory; otherwise we kick off a network
//      fetch in the background.
//   2. Every `refreshInterval` we hit the server with `If-None-Match` and
//      replace the cache only on a 200. A 304 leaves disk state alone.
//   3. Lookups go through `lookup(callsign:)` from any actor (nonisolated
//      via an internal lock).

import CarrierWaveData
import Foundation

// MARK: - CallsignEnrichmentCache

actor CallsignEnrichmentCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CallsignEnrichmentCache()

    /// Refresh interval — server polls upstream sources daily, so 12h here
    /// gives us a same-day update window without spamming the endpoint.
    static let refreshInterval: TimeInterval = 12 * 60 * 60

    /// Lookup a callsign's enrichment entry, if any. Always uppercases.
    nonisolated func lookup(callsign: String) -> CallsignEnrichmentEntry? {
        let upper = callsign.uppercased()
        return storage.read { $0.entries[upper] }
    }

    /// Snapshot of all known sources, for the chip emoji / display name.
    nonisolated func sources() -> [CallsignEnrichmentDatasetSource] {
        storage.read { $0.sources }
    }

    /// Status snapshot for settings UIs.
    func getStatus() -> ReferenceCacheStatus {
        status
    }

    /// Ensure the cache has been loaded at least once this process. Safe to
    /// call from multiple sites; subsequent calls are cheap.
    func ensureLoaded() async {
        if didLoad {
            return
        }
        didLoad = true

        // Load from disk if available.
        if let snapshot = Self.loadFromDisk() {
            storage.write { $0 = snapshot.payload }
            status = .loaded(
                recordCount: snapshot.payload.entries.count,
                downloadedAt: snapshot.downloadedAt
            )
            // Background refresh if stale.
            if Date().timeIntervalSince(snapshot.downloadedAt) > Self.refreshInterval {
                Task { await self.refreshIfNeeded() }
            }
            return
        }

        status = .downloading
        Task { await self.refreshIfNeeded(force: true) }
    }

    /// Force a refresh even if disk cache is fresh.
    func forceRefresh() async throws {
        try await refresh(force: true)
    }

    /// Refresh if stale; never throws.
    func refreshIfNeeded(force: Bool = false) async {
        do {
            try await refresh(force: force)
        } catch {
            // Keep whatever's already in memory; just log status.
            if case .loaded = status {
                // leave as-is so a transient failure doesn't break lookups
            } else {
                status = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Private

    private struct InMemory {
        var sources: [CallsignEnrichmentDatasetSource] = []
        var entries: [String: CallsignEnrichmentEntry] = [:]
        var generatedAt: Date?
    }

    private struct DiskSnapshot: Codable {
        let etag: String?
        let downloadedAt: Date
        let dataset: CallsignEnrichmentDataset

        var payload: InMemory {
            InMemory(
                sources: dataset.sources,
                entries: dataset.indexedByCallsign(),
                generatedAt: dataset.generatedAt
            )
        }
    }

    /// Lock-protected storage so nonisolated lookups don't have to await.
    private final class LockedStorage: @unchecked Sendable {
        // MARK: Internal

        func read<T>(_ body: (InMemory) -> T) -> T {
            lock.withLock { body(value) }
        }

        func write(_ body: (inout InMemory) -> Void) {
            lock.withLock { body(&value) }
        }

        // MARK: Private

        private let lock = NSLock()
        private var value = InMemory()
    }

    nonisolated private static let storage = LockedStorage()
    private static let cacheFileName = "callsign_enrichment.json"

    private static var cacheFileURL: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFileName)
    }

    private var didLoad = false
    private var status: ReferenceCacheStatus = .notLoaded
    private var lastETag: String?

    nonisolated private var storage: LockedStorage {
        Self.storage
    }

    private static func loadFromDisk() -> DiskSnapshot? {
        guard let data = try? Data(contentsOf: cacheFileURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiskSnapshot.self, from: data)
    }

    private static func saveToDisk(_ snapshot: DiskSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        try? data.write(to: cacheFileURL, options: .atomic)
    }

    private func refresh(force: Bool) async throws {
        // Decide whether to send If-None-Match based on the disk snapshot's
        // age; force=true skips the check.
        let etagToSend: String?
        if force {
            etagToSend = nil
        } else if let snapshot = Self.loadFromDisk(),
                  Date().timeIntervalSince(snapshot.downloadedAt) <= Self.refreshInterval
        {
            // Already fresh — nothing to do.
            return
        } else {
            etagToSend = lastETag ?? Self.loadFromDisk()?.etag
        }

        status = .downloading
        let client = await ActivitiesClient()
        let result = try await client.fetchCallsignEnrichmentDataset(
            currentETag: etagToSend
        )

        switch result {
        case let .updated(dataset, etag):
            let snapshot = DiskSnapshot(
                etag: etag,
                downloadedAt: Date(),
                dataset: dataset
            )
            Self.saveToDisk(snapshot)
            lastETag = etag
            storage.write { $0 = snapshot.payload }
            status = .loaded(
                recordCount: dataset.callsigns.count,
                downloadedAt: snapshot.downloadedAt
            )
        case .notModified:
            // Bump the disk timestamp so we don't re-hit the server every
            // launch when the data hasn't changed.
            if let existing = Self.loadFromDisk() {
                let bumped = DiskSnapshot(
                    etag: existing.etag,
                    downloadedAt: Date(),
                    dataset: existing.dataset
                )
                Self.saveToDisk(bumped)
                status = .loaded(
                    recordCount: bumped.dataset.callsigns.count,
                    downloadedAt: bumped.downloadedAt
                )
            }
        }
    }
}
