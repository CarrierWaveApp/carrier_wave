// POTA Parks Cache
//
// In-memory query surface over the POTA park reference data owned by the
// Rust core (`ReferenceDataApi` over the encrypted `pota_park` table).
// Hydrates a dictionary + name index from the store for full-text search
// and nearby parks lookup; download, parse, and storage live in Rust.

import CarrierWaveData
import Foundation

// MARK: - POTAPark

/// Full park metadata from the POTA reference dataset
struct POTAPark: Codable {
    let reference: String // "US-1234"
    let name: String // "Yellowstone National Park"
    let locationDesc: String // "US-WY" (state/region)
    let latitude: Double?
    let longitude: Double?
    let grid: String?
    let entityId: Int // DXCC entity (291 = USA)
    let isActive: Bool

    /// Extract country prefix from reference (e.g., "US" from "US-1234")
    nonisolated var countryPrefix: String {
        let parts = reference.split(separator: "-")
        guard let first = parts.first else {
            return ""
        }
        return String(first)
    }

    /// Extract numeric part from reference (e.g., "1234" from "US-1234")
    var numericPart: String {
        let parts = reference.split(separator: "-")
        guard parts.count >= 2 else {
            return ""
        }
        return String(parts[1])
    }

    /// Extract all US state abbreviations from locationDesc.
    /// Handles multi-state parks (e.g., "US-WY,US-MT" → ["WY", "MT"]).
    nonisolated var states: [String] {
        locationDesc.split(separator: ",")
            .compactMap { location in
                let trimmed = location.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.split(separator: "-")
                guard parts.count >= 2 else {
                    return nil
                }
                return String(parts[1])
            }
    }

    /// Extract primary state from locationDesc (e.g., "WY" from "US-WY").
    /// For multi-state parks, returns the first state.
    var state: String? {
        states.first
    }
}

// MARK: - POTAParksCache

actor POTAParksCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    /// Thread-safe container for parks and name index data, protected by NSLock.
    nonisolated final class LockedParksStorage: @unchecked Sendable {
        // MARK: Internal

        func withParks<T>(_ body: (inout [String: POTAPark]) -> T) -> T {
            lock.withLock { body(&parks) }
        }

        func withNameIndex<T>(_ body: (inout [(word: String, refs: [String])]) -> T) -> T {
            lock.withLock { body(&nameIndex) }
        }

        // MARK: Private

        private let lock = NSLock()
        private var parks: [String: POTAPark] = [:]
        private var nameIndex: [(word: String, refs: [String])] = []
    }

    static let shared = POTAParksCache()

    /// Current status of the cache (for UI display)
    private(set) var status: ReferenceCacheStatus = .notLoaded

    /// Number of parks in cache (for display/debugging)
    var parkCount: Int {
        storage.withParks { $0.count }
    }

    /// Get park name for a reference (e.g., "K-1234" -> "Yellowstone National Park")
    func name(for reference: String) -> String? {
        storage.withParks { $0[reference.uppercased()]?.name }
    }

    /// Get full park data for a reference
    func park(for reference: String) -> POTAPark? {
        storage.withParks { $0[reference.uppercased()] }
    }

    /// Ensure the in-memory cache is hydrated from the Rust store.
    /// If the store is empty (first launch), downloads via the core first.
    func ensureLoaded() async {
        guard storage.withParks({ $0.isEmpty }) else {
            return
        }

        status = .loading
        do {
            let api = try await ReferenceData.api()
            let storedParks = try api.status().potaParks.count
            if storedParks < 1 {
                status = .downloading
                _ = try await api.refreshPotaParks(force: false)
            }
            try hydrate(from: api)
            status = try loadedStatus(from: api)
            Task { await refreshIfNeeded() }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Check if the store's dataset is stale and refresh if needed (14-day
    /// TTL enforced by the Rust core). Re-hydrates on a fresh download.
    func refreshIfNeeded() async {
        do {
            let api = try await ReferenceData.api()
            let outcome = try await api.refreshPotaParks(force: false)
            if outcome.refreshed {
                try hydrate(from: api)
                status = try loadedStatus(from: api)
            }
        } catch {
            // Background refresh failure -- keep serving the hydrated data.
        }
    }

    /// Force refresh the cache, throwing on failure
    func forceRefresh() async throws {
        status = .downloading
        do {
            let api = try await ReferenceData.api()
            _ = try await api.refreshPotaParks(force: true)
            try hydrate(from: api)
            status = try loadedStatus(from: api)
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Last download date (for display/debugging)
    func lastDownloadDate() async -> Date? {
        guard let api = try? await ReferenceData.api(),
              let fetchedAt = try? api.status().potaParks.fetchedAt
        else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(fetchedAt))
    }

    /// Get current status snapshot for UI
    func getStatus() -> ReferenceCacheStatus {
        status
    }

    /// Synchronous park name lookup for UI use (nonisolated for MainActor access)
    nonisolated func nameSync(for reference: String) -> String? {
        storage.withParks { $0[reference.uppercased()]?.name }
    }

    /// Synchronous full park lookup for UI use (nonisolated for MainActor access)
    nonisolated func parkSync(for reference: String) -> POTAPark? {
        storage.withParks { $0[reference.uppercased()] }
    }

    /// Lookup a park by reference, supporting shorthand notation
    nonisolated func lookupPark(_ query: String, defaultCountry: String = "US") -> POTAPark? {
        let trimmed = query.trimmingCharacters(in: .whitespaces).uppercased()

        return storage.withParks { parks in
            if let park = parks[trimmed] {
                return park
            }

            if trimmed.allSatisfy(\.isNumber) {
                let withPrefix = "\(defaultCountry.uppercased())-\(trimmed)"
                return parks[withPrefix]
            }

            if trimmed.hasPrefix("K-") {
                let usRef = "US-" + trimmed.dropFirst(2)
                return parks[String(usRef)]
            }

            return nil
        }
    }

    // MARK: Internal (lock-protected accessors for extensions in other files)

    /// Return a snapshot of the parks dictionary under the lock.
    nonisolated func parksSnapshot() -> [String: POTAPark] {
        storage.withParks { $0 }
    }

    /// Return a park by reference under the lock.
    nonisolated func park(inStorage reference: String) -> POTAPark? {
        storage.withParks { $0[reference] }
    }

    /// Return a snapshot of the name index under the lock.
    nonisolated func nameIndexSnapshot() -> [(word: String, refs: [String])] {
        storage.withNameIndex { $0 }
    }

    /// Release in-memory data under memory pressure. Data reloads on next access.
    func clearForMemoryPressure() {
        storage.withParks { $0.removeAll() }
        storage.withNameIndex { $0.removeAll() }
        status = .notLoaded
    }

    // MARK: Private

    /// Thread-safe storage container accessible from nonisolated context.
    nonisolated private let storage = LockedParksStorage()

    /// Rebuild the in-memory dictionary + name index from the Rust store,
    /// paging through `pota_park` in bounded batches.
    private func hydrate(from api: ReferenceDataApi) throws {
        var parks: [String: POTAPark] = [:]
        var offset: Int64 = 0
        while true {
            let page = try api.potaParksPage(limit: ReferenceData.pageSize, offset: offset)
            for row in page {
                let reference = row.reference.uppercased()
                parks[reference] = POTAPark(
                    reference: reference,
                    name: row.name,
                    locationDesc: row.locationDesc,
                    latitude: row.latitude,
                    longitude: row.longitude,
                    grid: row.grid,
                    entityId: Int(row.entityId),
                    isActive: row.isActive
                )
            }
            if Int64(page.count) < ReferenceData.pageSize {
                break
            }
            offset += ReferenceData.pageSize
        }
        storage.withParks { $0 = parks }
        buildNameIndex()
    }

    /// Build a `.loaded` status from the store's dataset status.
    private func loadedStatus(from api: ReferenceDataApi) throws -> ReferenceCacheStatus {
        let dataset = try api.status().potaParks
        let downloadedAt = dataset.fetchedAt.map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }
        return .loaded(recordCount: Int(dataset.count), downloadedAt: downloadedAt)
    }

    /// Build sorted name index for O(log n) prefix search
    private func buildNameIndex() {
        var index: [String: [String]] = [:]
        let snapshot = storage.withParks { $0 }

        for (reference, park) in snapshot {
            let nameWords = park.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }

            let refWords = reference.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            for word in nameWords + refWords {
                index[word, default: []].append(reference)
            }
        }

        let built = index
            .map { (word: $0.key, refs: $0.value) }
            .sorted { $0.word < $1.word }
        storage.withNameIndex { $0 = built }
    }
}
