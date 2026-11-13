// Callsign Enrichment Store (CW Sweep)
//
// macOS counterpart of CallsignEnrichmentCache on iOS. Pulls the
// activities-server enrichment dataset (CWops + future SKCC etc.),
// caches it to disk with an ETag, and exposes O(1) callsign lookup.
//
// Mirrors the structure of PoloNotesStore so settings/log surfaces can
// treat it the same way.

import CarrierWaveData
import Foundation
import OSLog

actor CallsignEnrichmentStore {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CallsignEnrichmentStore()

    /// Refresh the dataset at most every 12h so a same-day server update
    /// makes it to clients without spamming the endpoint on every launch.
    static let stalenessInterval: TimeInterval = 12 * 60 * 60

    /// Synchronous lookup for SwiftUI bodies — backed by an `NSLock`.
    nonisolated func lookup(callsign: String) -> CallsignEnrichmentEntry? {
        let upper = callsign.uppercased()
        return Self.storage.read { $0.entries[upper] }
    }

    /// Sources snapshot for chip rendering / settings UIs.
    nonisolated func sources() -> [CallsignEnrichmentDatasetSource] {
        Self.storage.read { $0.sources }
    }

    /// Load disk cache and refresh in the background if stale.
    func ensureLoaded() async {
        guard !didLoad else {
            return
        }
        didLoad = true

        if let snapshot = Self.loadFromDisk() {
            Self.storage.write { $0 = snapshot.payload }
            if Date().timeIntervalSince(snapshot.downloadedAt) > Self.stalenessInterval {
                Task { await self.refresh() }
            }
            return
        }

        Task { await self.refresh() }
    }

    /// Fetch fresh dataset from server.
    func refresh() async {
        let baseURL = Self.resolvedBaseURL
        guard let url = URL(string: baseURL + "/v1/callsign-enrichment/dataset") else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("CWSweep/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = lastETag ?? Self.loadFromDisk()?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return
            }
            if http.statusCode == 304 {
                if let snapshot = Self.loadFromDisk() {
                    let bumped = DiskSnapshot(
                        etag: snapshot.etag,
                        downloadedAt: Date(),
                        dataset: snapshot.dataset
                    )
                    Self.saveToDisk(bumped)
                }
                return
            }
            guard (200 ... 299).contains(http.statusCode) else {
                Self.logger.warning(
                    "callsign enrichment fetch HTTP \(http.statusCode)"
                )
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let dataset = try decoder.decode(CallsignEnrichmentDataset.self, from: data)
            let etag = http.value(forHTTPHeaderField: "Etag")
                ?? http.value(forHTTPHeaderField: "ETag")
            let snapshot = DiskSnapshot(
                etag: etag,
                downloadedAt: Date(),
                dataset: dataset
            )
            Self.saveToDisk(snapshot)
            lastETag = etag
            Self.storage.write { $0 = snapshot.payload }
        } catch {
            Self.logger.warning("callsign enrichment fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    private struct InMemory {
        var sources: [CallsignEnrichmentDatasetSource] = []
        var entries: [String: CallsignEnrichmentEntry] = [:]
    }

    private struct DiskSnapshot: Codable {
        let etag: String?
        let downloadedAt: Date
        let dataset: CallsignEnrichmentDataset

        var payload: InMemory {
            InMemory(
                sources: dataset.sources,
                entries: dataset.indexedByCallsign()
            )
        }
    }

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
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CWSweep",
        category: "CallsignEnrichmentStore"
    )

    nonisolated private static var resolvedBaseURL: String {
        let override = UserDefaults.standard.string(forKey: "activitiesServerURLOverride") ?? ""
        if override.isEmpty {
            return "https://activities.carrierwave.app"
        }
        return override
    }

    private static var cacheFileURL: URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("callsign_enrichment.json")
    }

    private var didLoad = false
    private var lastETag: String?

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
}
