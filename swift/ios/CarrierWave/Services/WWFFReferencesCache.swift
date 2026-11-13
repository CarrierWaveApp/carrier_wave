// WWFF References Cache
//
// In-memory query surface over the WWFF reference directory owned by the
// Rust core (`ReferenceDataApi` handles download, parse, and storage).
// Hydrates from paged store reads and supports full-text search and
// nearby references lookup. Active-status filtering stays at query time.

import CarrierWaveData
import Foundation

// MARK: - WWFFReferencesCache

actor WWFFReferencesCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    /// Thread-safe container for references and name index data, protected by NSLock.
    nonisolated final class LockedRefsStorage: @unchecked Sendable {
        // MARK: Internal

        func withRefs<T>(_ body: (inout [String: WWFFReference]) -> T) -> T {
            lock.withLock { body(&refs) }
        }

        func withNameIndex<T>(_ body: (inout [(word: String, codes: [String])]) -> T) -> T {
            lock.withLock { body(&nameIndex) }
        }

        // MARK: Private

        private let lock = NSLock()
        private var refs: [String: WWFFReference] = [:]
        private var nameIndex: [(word: String, codes: [String])] = []
    }

    static let shared = WWFFReferencesCache()

    /// Current status of the cache (for UI display)
    private(set) var status: ReferenceCacheStatus = .notLoaded

    /// Number of references in cache
    var referenceCount: Int {
        storage.withRefs { $0.count }
    }

    /// Get reference name for a code (e.g., "KFF-1234" -> "Yellowstone NP")
    func name(for code: String) -> String? {
        storage.withRefs { $0[code.uppercased()]?.name }
    }

    /// Get full reference data for a code
    func reference(for code: String) -> WWFFReference? {
        storage.withRefs { $0[code.uppercased()] }
    }

    // MARK: Internal (lock-protected accessors for extensions in other files)

    /// Return a snapshot of the references dictionary under the lock.
    nonisolated func referencesSnapshot() -> [String: WWFFReference] {
        storage.withRefs { $0 }
    }

    /// Store a new name index under the lock.
    func storeNameIndex(_ index: [(word: String, codes: [String])]) {
        storage.withNameIndex { $0 = index }
    }

    /// Ensure cache is hydrated from the store, downloading if the store is empty
    func ensureLoaded() async {
        guard !isLoaded else {
            return
        }

        status = .loading

        do {
            let api = try await ReferenceData.api()
            let dataset = try api.status().wwffReferences
            guard dataset.count >= 1 else {
                // Store empty -- download in background, don't block caller.
                // Lookups return nil until the download completes.
                isLoaded = true
                status = .downloading
                Task { await downloadAndHydrate(api: api) }
                return
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
            let outcome = try await api.refreshWwffDirectory(force: false)
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
            _ = try await api.refreshWwffDirectory(force: true)
            try hydrate(from: api)
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Last download date from the store's dataset status
    func lastDownloadDate() async -> Date? {
        guard let api = try? await ReferenceData.api(),
              let dataset = try? api.status().wwffReferences,
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

    /// Synchronous name lookup (nonisolated for MainActor access)
    nonisolated func nameSync(for code: String) -> String? {
        storage.withRefs { $0[code.uppercased()]?.name }
    }

    /// Synchronous full reference lookup (nonisolated for MainActor access)
    nonisolated func referenceSync(for code: String) -> WWFFReference? {
        storage.withRefs { $0[code.uppercased()] }
    }

    /// Look up a reference by exact code
    nonisolated func lookupReference(_ code: String) -> WWFFReference? {
        storage.withRefs { $0[code.trimmingCharacters(in: .whitespaces).uppercased()] }
    }

    /// Search references by name (full-text search on words)
    nonisolated func searchByName(_ query: String, limit: Int = 20) -> [WWFFReference] {
        let indexSnapshot = storage.withNameIndex { $0 }
        let codes = NameIndexSearch.searchByName(query, in: indexSnapshot, limit: limit * 2)
        guard !codes.isEmpty else {
            return []
        }

        var results = codes.compactMap { code in storage.withRefs { $0[code] } }
            .filter { $0.status == "active" }
        results.sort { lhs, rhs in
            if lhs.name.count != rhs.name.count {
                return lhs.name.count < rhs.name.count
            }
            return lhs.name < rhs.name
        }

        return Array(results.prefix(limit))
    }

    /// Find references near a location
    nonisolated func nearbyReferences(
        latitude: Double,
        longitude: Double,
        limit: Int = 20,
        maxDistanceKm: Double = 100
    ) -> [(reference: WWFFReference, distanceKm: Double)] {
        var results: [(reference: WWFFReference, distanceKm: Double)] = []
        let snapshot = storage.withRefs { $0 }

        for ref in snapshot.values {
            guard ref.status == "active",
                  let rLat = ref.latitude, let rLon = ref.longitude
            else {
                continue
            }

            let distance = HaversineDistance.distance(
                lat1: latitude, lon1: longitude,
                lat2: rLat, lon2: rLon
            )

            if distance <= maxDistanceKm {
                results.append((reference: ref, distanceKm: distance))
            }
        }

        results.sort { $0.distanceKm < $1.distanceKm }
        return Array(results.prefix(limit))
    }

    /// Release in-memory data under memory pressure. Data reloads on next access.
    func clearForMemoryPressure() {
        storage.withRefs { $0.removeAll() }
        storage.withNameIndex { $0.removeAll() }
        isLoaded = false
        status = .notLoaded
    }

    // MARK: Private

    /// Thread-safe storage container accessible from nonisolated context.
    nonisolated private let storage = LockedRefsStorage()

    private var isLoaded = false

    /// Download via the Rust core (respects its TTL) and hydrate on success.
    private func downloadAndHydrate(api: ReferenceDataApi) async {
        status = .downloading
        do {
            _ = try await api.refreshWwffDirectory(force: false)
            try hydrate(from: api)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Hydrate the in-memory dictionary from paged store reads, rebuild the
    /// name index, and update status from the store's dataset status.
    private func hydrate(from api: ReferenceDataApi) throws {
        var refs: [String: WWFFReference] = [:]
        var offset: Int64 = 0
        while true {
            let page = try api.wwffReferencesPage(
                limit: ReferenceData.pageSize, offset: offset
            )
            for item in page {
                refs[item.reference.uppercased()] = WWFFReference(ffi: item)
            }
            if Int64(page.count) < ReferenceData.pageSize {
                break
            }
            offset += ReferenceData.pageSize
        }

        storage.withRefs { $0 = refs }
        buildNameIndex()
        isLoaded = true

        let dataset = try api.status().wwffReferences
        status = .loaded(
            recordCount: refs.count,
            downloadedAt: dataset.fetchedAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
        )
    }
}

// MARK: - WWFFReference + FFI

nonisolated extension WWFFReference {
    /// Map a Rust store row onto the app model.
    init(ffi: FfiWwffReference) {
        self.init(
            reference: ffi.reference,
            name: ffi.name,
            program: ffi.program,
            status: ffi.status,
            continent: ffi.continent,
            iota: ffi.iota,
            grid: ffi.grid,
            latitude: ffi.latitude,
            longitude: ffi.longitude,
            iucnCategory: ffi.iucnCategory,
            country: ffi.country,
            region: ffi.region,
            dxccEntity: ffi.dxccEntity.map { Int($0) }
        )
    }
}
