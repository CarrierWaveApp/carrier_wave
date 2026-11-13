// SOTA Summits Cache
//
// In-memory query surface over the SOTA summit database owned by the
// Rust core (`ReferenceDataApi` handles download, parse, and storage;
// expired summits are filtered at parse time in Rust). Hydrates from
// paged store reads and supports full-text search and nearby lookup.

import CarrierWaveData
import Foundation

// MARK: - SOTASummitsCache

actor SOTASummitsCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    /// Thread-safe container for summits and name index data, protected by NSLock.
    nonisolated final class LockedSummitsStorage: @unchecked Sendable {
        // MARK: Internal

        func withSummits<T>(_ body: (inout [String: SOTASummit]) -> T) -> T {
            lock.withLock { body(&summits) }
        }

        func withNameIndex<T>(_ body: (inout [(word: String, codes: [String])]) -> T) -> T {
            lock.withLock { body(&nameIndex) }
        }

        // MARK: Private

        private let lock = NSLock()
        private var summits: [String: SOTASummit] = [:]
        private var nameIndex: [(word: String, codes: [String])] = []
    }

    static let shared = SOTASummitsCache()

    /// Current status of the cache (for UI display)
    private(set) var status: ReferenceCacheStatus = .notLoaded

    /// Number of summits in cache
    var summitCount: Int {
        storage.withSummits { $0.count }
    }

    // MARK: Internal (lock-protected accessors for extensions in other files)

    /// Return a snapshot of the summits dictionary under the lock.
    nonisolated func summitsSnapshot() -> [String: SOTASummit] {
        storage.withSummits { $0 }
    }

    /// Store a new summits dictionary under the lock.
    func storeSummits(_ newSummits: [String: SOTASummit]) {
        storage.withSummits { $0 = newSummits }
    }

    /// Store a new name index under the lock.
    func storeNameIndex(_ index: [(word: String, codes: [String])]) {
        storage.withNameIndex { $0 = index }
    }

    /// Get summit name for a code (e.g., "W4C/CM-001" -> "Mount Mitchell")
    func name(for code: String) -> String? {
        storage.withSummits { $0[code.uppercased()]?.name }
    }

    /// Get full summit data for a code
    func summit(for code: String) -> SOTASummit? {
        storage.withSummits { $0[code.uppercased()] }
    }

    /// Ensure cache is hydrated from the store, downloading via the Rust
    /// core first if the store is empty
    func ensureLoaded() async {
        guard !isLoaded else {
            return
        }

        status = .loading

        do {
            let api = try await ReferenceData.api()
            let storedSummits = try api.status().sotaSummits.count
            if storedSummits < 1 {
                status = .downloading
                _ = try await api.refreshSotaSummits(force: false)
            }
            try hydrate(from: api)
            Task { await refreshIfNeeded() }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Refresh via the Rust core (30-day TTL) and re-hydrate if data changed
    func refreshIfNeeded() async {
        do {
            let api = try await ReferenceData.api()
            let outcome = try await api.refreshSotaSummits(force: false)
            if outcome.refreshed {
                try hydrate(from: api)
            }
        } catch {
            // Keep serving the current in-memory data on refresh failure.
        }
    }

    /// Force refresh the cache, throwing on failure
    func forceRefresh() async throws {
        status = .downloading
        do {
            let api = try await ReferenceData.api()
            _ = try await api.refreshSotaSummits(force: true)
            try hydrate(from: api)
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Last download date from the store's dataset status
    func lastDownloadDate() async -> Date? {
        guard let api = try? await ReferenceData.api(),
              let dataset = try? api.status().sotaSummits,
              let fetchedAt = dataset.fetchedAt
        else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(fetchedAt))
    }

    /// Get current status snapshot for UI
    func getStatus() -> ReferenceCacheStatus {
        status
    }

    /// Synchronous summit name lookup (nonisolated for MainActor access)
    nonisolated func nameSync(for code: String) -> String? {
        storage.withSummits { $0[code.uppercased()]?.name }
    }

    /// Synchronous full summit lookup (nonisolated for MainActor access)
    nonisolated func summitSync(for code: String) -> SOTASummit? {
        storage.withSummits { $0[code.uppercased()] }
    }

    /// Look up a summit by exact code
    nonisolated func lookupSummit(_ code: String) -> SOTASummit? {
        storage.withSummits { $0[code.trimmingCharacters(in: .whitespaces).uppercased()] }
    }

    /// Search summits by name (full-text search on words)
    nonisolated func searchByName(_ query: String, limit: Int = 20) -> [SOTASummit] {
        let indexSnapshot = storage.withNameIndex { $0 }
        let codes = NameIndexSearch.searchByName(query, in: indexSnapshot, limit: limit * 2)
        guard !codes.isEmpty else {
            return []
        }

        var results = codes.compactMap { code in storage.withSummits { $0[code] } }
        results.sort { lhs, rhs in
            if lhs.name.count != rhs.name.count {
                return lhs.name.count < rhs.name.count
            }
            return lhs.name < rhs.name
        }

        return Array(results.prefix(limit))
    }

    nonisolated func nearbySummits(
        latitude: Double,
        longitude: Double,
        limit: Int = 20,
        maxDistanceKm: Double = 100
    ) -> [(summit: SOTASummit, distanceKm: Double)] {
        var results: [(summit: SOTASummit, distanceKm: Double)] = []
        let snapshot = storage.withSummits { $0 }

        for summit in snapshot.values {
            guard let sLat = summit.latitude, let sLon = summit.longitude else {
                continue
            }

            let distance = haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: sLat, lon2: sLon
            )

            if distance <= maxDistanceKm {
                results.append((summit: summit, distanceKm: distance))
            }
        }

        results.sort { $0.distanceKm < $1.distanceKm }
        return Array(results.prefix(limit))
    }

    /// Release in-memory data under memory pressure. Data reloads on next access.
    func clearForMemoryPressure() {
        storage.withSummits { $0.removeAll() }
        storage.withNameIndex { $0.removeAll() }
        isLoaded = false
        status = .notLoaded
    }

    // MARK: Private

    /// Thread-safe storage container accessible from nonisolated context.
    nonisolated private let storage = LockedSummitsStorage()

    private var isLoaded = false

    /// Hydrate the in-memory dictionary from paged store reads, rebuild the
    /// name index, and update status from the store's dataset status.
    /// Runs on the actor's executor, never the main actor.
    private func hydrate(from api: ReferenceDataApi) throws {
        var summits: [String: SOTASummit] = [:]
        var offset: Int64 = 0
        while true {
            let page = try api.sotaSummitsPage(
                limit: ReferenceData.pageSize, offset: offset
            )
            for item in page {
                summits[item.code.uppercased()] = SOTASummit(ffi: item)
            }
            if Int64(page.count) < ReferenceData.pageSize {
                break
            }
            offset += ReferenceData.pageSize
        }

        storeSummits(summits)
        buildNameIndex()
        isLoaded = true

        let dataset = try api.status().sotaSummits
        status = .loaded(
            recordCount: summits.count,
            downloadedAt: dataset.fetchedAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
        )
    }
}

// MARK: - SOTASummit + FFI

nonisolated extension SOTASummit {
    /// Map an FFI summit row into the app's model shape.
    init(ffi: FfiSotaSummit) {
        self.init(
            code: ffi.code.uppercased(),
            name: ffi.name,
            associationName: ffi.associationName,
            regionName: ffi.regionName,
            altitudeM: Int(ffi.altitudeM),
            altitudeFt: Int(ffi.altitudeFt),
            latitude: ffi.latitude,
            longitude: ffi.longitude,
            points: Int(ffi.points),
            bonusPoints: Int(ffi.bonusPoints),
            activationCount: Int(ffi.activationCount),
            lastActivationDate: ffi.lastActivationDate,
            lastActivationCall: ffi.lastActivationCall,
            grid: ffi.grid
        )
    }
}
