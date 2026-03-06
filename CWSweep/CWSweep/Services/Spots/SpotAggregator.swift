import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import Foundation
import SwiftData

/// Single source of truth for all spot data.
/// Polls HTTP sources in parallel, deduplicates, enriches with distance/region,
/// and persists to SwiftData for iCloud sync.
@MainActor
@Observable
final class SpotAggregator {
    // MARK: Internal

    // MARK: - Published State

    private(set) var spots: [EnrichedSpot] = []
    private(set) var isPolling = false
    private(set) var lastRefresh: Date?
    private(set) var spotCounts: [SpotSource: Int] = [:]
    private(set) var errors: [SpotSource: String] = [:]

    // MARK: - Configuration

    /// User's callsign (for self-spot detection and RBN queries)
    var userCallsign: String = ""

    /// User's grid square (for distance calculation)
    var userGrid: String = ""

    /// Poll interval in seconds
    var pollInterval: TimeInterval = 30

    /// Maximum spot age before pruning
    var maxSpotAge: TimeInterval = 1_800 // 30 minutes

    /// Start polling all spot sources
    func startPolling() {
        guard !isPolling else {
            return
        }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchAllSpots()
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 30))
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        isPolling = false
        pollTask?.cancel()
        pollTask = nil
    }

    /// Manually trigger a refresh
    func refresh() async {
        await fetchAllSpots()
    }

    /// Add spots from a DX cluster connection
    func addClusterSpots(_ clusterSpots: [UnifiedSpot]) {
        let now = Date()
        // Merge cluster spots into the unified pool
        for spot in clusterSpots {
            unifiedSpots[spot.dedupKey] = spot
        }
        // Re-enrich and publish
        enrichAndPublish()
        lastRefresh = now
    }

    // MARK: - SwiftData Persistence

    /// Persist current spots to SwiftData for iCloud sync
    func persistToSwiftData(modelContext: ModelContext, loggingSessionId: UUID) {
        // Delete stale spots for this session
        let cutoff = Date().addingTimeInterval(-maxSpotAge)
        let descriptor = FetchDescriptor<SessionSpot>(
            predicate: #Predicate { $0.loggingSessionId == loggingSessionId && $0.timestamp < cutoff }
        )
        if let stale = try? modelContext.fetch(descriptor) {
            for spot in stale {
                modelContext.delete(spot)
            }
        }

        // Upsert current spots
        for enriched in spots {
            let spot = enriched.spot
            let sessionSpot = SessionSpot(
                loggingSessionId: loggingSessionId,
                callsign: spot.callsign,
                frequencyKHz: spot.frequencyKHz,
                mode: spot.mode,
                timestamp: spot.timestamp,
                source: spot.source.rawValue,
                snr: spot.snr,
                wpm: spot.wpm,
                spotter: spot.spotter,
                spotterGrid: spot.spotterGrid,
                parkRef: spot.parkRef,
                parkName: spot.parkName,
                comments: spot.comments,
                region: enriched.region.rawValue,
                distanceMeters: enriched.distanceMeters
            )
            modelContext.insert(sessionSpot)
        }

        try? modelContext.save()
    }

    // MARK: Private

    /// Source priority for deduplication (higher index = higher priority)
    private static let sourcePriority: [SpotSource: Int] = [
        .rbn: 0,
        .wwff: 1,
        .sota: 2,
        .pota: 3,
        .cluster: 4,
    ]

    private var pollTask: Task<Void, Never>?

    // Spot clients (actors)
    private let rbnClient = RBNClient()
    private let potaClient = POTASpotsClient()
    private let sotaClient = SOTAClient()
    private let wwffClient = WWFFClient()
    private let gridCache = GridCache.shared
    private let stateCache = CallsignStateCache.shared

    /// All unified spots keyed by dedupKey — callsign+band, preferring higher-priority source
    private var unifiedSpots: [String: UnifiedSpot] = [:]

    private func fetchAllSpots() async {
        let fetchStart = Date()

        // Fetch all sources in parallel — each independently error-handled
        async let rbnResult = fetchRBN()
        async let potaResult = fetchPOTA()
        async let sotaResult = fetchSOTA()
        async let wwffResult = fetchWWFF()

        let results = await (rbnResult, potaResult, sotaResult, wwffResult)

        // Merge results
        mergeSpots(results.0, source: .rbn)
        mergeSpots(results.1, source: .pota)
        mergeSpots(results.2, source: .sota)
        mergeSpots(results.3, source: .wwff)

        // Prune old spots
        pruneExpired()

        // Enrich and publish
        enrichAndPublish()

        lastRefresh = fetchStart

        // Update counts
        var counts: [SpotSource: Int] = [:]
        for spot in spots {
            counts[spot.spot.source, default: 0] += 1
        }
        spotCounts = counts
    }

    // MARK: - Source Fetchers

    private func fetchRBN() async -> [UnifiedSpot] {
        do {
            let rbnSpots = try await rbnClient.spots(limit: 100)
            errors.removeValue(forKey: .rbn)
            return rbnSpots.map { UnifiedSpot.from(rbn: $0) }
        } catch {
            errors[.rbn] = error.localizedDescription
            return []
        }
    }

    private func fetchPOTA() async -> [UnifiedSpot] {
        do {
            let potaSpots = try await potaClient.fetchActiveSpots()
            errors.removeValue(forKey: .pota)
            return potaSpots.compactMap { UnifiedSpot.from(pota: $0) }
        } catch {
            errors[.pota] = error.localizedDescription
            return []
        }
    }

    private func fetchSOTA() async -> [UnifiedSpot] {
        do {
            let sotaSpots = try await sotaClient.fetchSpots()
            errors.removeValue(forKey: .sota)
            return sotaSpots.compactMap { UnifiedSpot.from(sota: $0) }
        } catch {
            errors[.sota] = error.localizedDescription
            return []
        }
    }

    private func fetchWWFF() async -> [UnifiedSpot] {
        do {
            let wwffSpots = try await wwffClient.fetchSpots()
            errors.removeValue(forKey: .wwff)
            return wwffSpots.compactMap { UnifiedSpot.from(wwff: $0) }
        } catch {
            errors[.wwff] = error.localizedDescription
            return []
        }
    }

    // MARK: - Merging & Dedup

    private func mergeSpots(_ newSpots: [UnifiedSpot], source _: SpotSource) {
        for spot in newSpots {
            let key = spot.dedupKey
            if let existing = unifiedSpots[key] {
                let existingPriority = Self.sourcePriority[existing.source] ?? 0
                let newPriority = Self.sourcePriority[spot.source] ?? 0
                if newPriority >= existingPriority {
                    unifiedSpots[key] = spot
                }
            } else {
                unifiedSpots[key] = spot
            }
        }
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-maxSpotAge)
        unifiedSpots = unifiedSpots.filter { $0.value.timestamp > cutoff }
    }

    // MARK: - Enrichment

    private func enrichAndPublish() {
        let userCoord = userCoordinate()

        spots = unifiedSpots.values.map { spot in
            let region = SpotRegion.from(grid: spot.spotterGrid)
            let distance = distanceBetween(userCoord: userCoord, spotGrid: spot.spotterGrid)
            let bearing = bearingTo(spotGrid: spot.spotterGrid)

            return EnrichedSpot(
                spot: spot,
                distanceMeters: distance,
                bearingDegrees: bearing,
                region: region,
                state: spot.stateAbbr,
                country: nil
            )
        }
        .sorted { $0.spot.timestamp > $1.spot.timestamp }

        // Kick off async HamDB lookups for spots missing state info
        enrichWithHamDB()
    }

    /// Async HamDB lookups for spots missing state/country info (non-POTA spots)
    private func enrichWithHamDB() {
        let callsignsNeedingLookup = spots
            .filter { $0.state == nil && $0.country == nil }
            .map(\.spot.callsign)

        // Deduplicate
        let unique = Array(Set(callsignsNeedingLookup))

        // Limit concurrent lookups
        let batch = Array(unique.prefix(10))
        guard !batch.isEmpty else {
            return
        }

        Task { [weak self] in
            await withTaskGroup(of: (String, String?, String?).self) { group in
                for callsign in batch {
                    group.addTask {
                        // Check state cache first
                        if let cached = await CallsignStateCache.shared.get(callsign) {
                            return (callsign, cached, nil)
                        }
                        // Look up via HamDB
                        let client = HamDBClient()
                        guard let license = try? await client.lookup(callsign: callsign) else {
                            await CallsignStateCache.shared.set(callsign, state: nil)
                            return (callsign, nil, nil)
                        }
                        let state = license.state
                        let country = license.country
                        await CallsignStateCache.shared.set(callsign, state: state)
                        return (callsign, state, country)
                    }
                }

                var results: [String: (state: String?, country: String?)] = [:]
                for await (callsign, state, country) in group {
                    results[callsign] = (state, country)
                }

                // Apply results on MainActor
                self?.applyHamDBResults(results)
            }
        }
    }

    private func applyHamDBResults(_ results: [String: (state: String?, country: String?)]) {
        var updated = false
        for i in spots.indices {
            let callsign = spots[i].spot.callsign
            if let result = results[callsign] {
                if spots[i].state == nil, let state = result.state, !state.isEmpty {
                    spots[i].state = state
                    updated = true
                }
                if spots[i].country == nil, let country = result.country, !country.isEmpty {
                    spots[i].country = country
                    updated = true
                }
            }
        }
        _ = updated // Mutation on @Observable triggers view updates automatically
    }

    private func userCoordinate() -> CLLocationCoordinate2D? {
        guard !userGrid.isEmpty,
              let coord = MaidenheadConverter.coordinate(from: userGrid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    private func bearingTo(spotGrid: String?) -> Double? {
        guard !userGrid.isEmpty, let spotGrid else {
            return nil
        }
        return MaidenheadConverter.bearing(from: userGrid, to: spotGrid)
    }

    private func distanceBetween(
        userCoord: CLLocationCoordinate2D?,
        spotGrid: String?
    ) -> Double? {
        guard let userCoord,
              let grid = spotGrid,
              let spotCoord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        let userLocation = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let spotLocation = CLLocation(latitude: spotCoord.latitude, longitude: spotCoord.longitude)
        return userLocation.distance(from: spotLocation)
    }
}
