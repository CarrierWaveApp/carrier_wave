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

    // MARK: Internal (extension access)

    /// Source priority for deduplication (higher index = higher priority)
    static let sourcePriority: [SpotSource: Int] = [
        .rbn: 0,
        .wwff: 1,
        .sota: 2,
        .pota: 3,
        .dxSummit: 4,
        .dxHeat: 5,
        .dxWatch: 6,
        .cluster: 7,
    ]

    // MARK: - Published State

    /// Enriched spots — writable from extension for enrichment
    var spots: [EnrichedSpot] = []
    /// Incremented when spot enrichment data changes (triggers UI refresh)
    var spotsVersion = 0
    private(set) var isPolling = false
    private(set) var lastRefresh: Date?
    private(set) var spotCounts: [SpotSource: Int] = [:]
    private(set) var errors: [SpotSource: String] = [:]

    // MARK: - Configuration

    /// User's callsign (for self-spot detection and RBN queries)
    var userCallsign: String = ""

    /// User's grid square (for distance calculation)
    var userGrid: String = ""

    /// DXCC lookup service for entity resolution
    var dxccLookup: DXCCLookupService?

    /// DXCC needed checker for award status
    var neededChecker: DXCCNeededChecker?

    /// Poll interval in seconds
    var pollInterval: TimeInterval = 30

    /// Maximum spot age before pruning
    var maxSpotAge: TimeInterval = 1_800 // 30 minutes

    var pollTask: Task<Void, Never>?
    var enrichmentTask: Task<Void, Never>?

    // Spot clients (actors)
    let rbnClient = RBNClient()
    let potaClient = POTASpotsClient()
    let sotaClient = SOTAClient()
    let wwffClient = WWFFClient()
    let dxSummitClient = DXSummitClient()
    let dxHeatClient = DXHeatClient()
    let dxWatchClient = DXWatchClient()
    let gridCache = GridCache.shared
    let stateCache = CallsignStateCache.shared

    /// All unified spots keyed by dedupKey — callsign+band, preferring higher-priority source
    var unifiedSpots: [String: UnifiedSpot] = [:]

    /// Cached callsign enrichment data (survives spot rebuilds)
    var callsignEnrichmentCache: [String: CallsignEnrichment] = [:]

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
        var deleted: [SessionSpot] = []
        if let stale = try? modelContext.fetch(descriptor) {
            deleted = stale
        }

        // Upsert current spots
        var inserted: [SessionSpot] = []
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
            inserted.append(sessionSpot)
        }

        // The batch deletes stale rows from SwiftData itself (and from
        // cw-store first under `.on`).
        try? CwStoreSeams.save(modelContext, spots: inserted, deletedSpots: deleted)
    }

    func fetchAllSpots() async {
        let fetchStart = Date()

        // Fetch all sources in parallel — each independently error-handled
        async let rbnResult = fetchRBN()
        async let potaResult = fetchPOTA()
        async let sotaResult = fetchSOTA()
        async let wwffResult = fetchWWFF()
        async let dxSummitResult = fetchDXSummit()
        async let dxHeatResult = fetchDXHeat()
        async let dxWatchResult = fetchDXWatch()

        let results = await (
            rbnResult, potaResult, sotaResult, wwffResult,
            dxSummitResult, dxHeatResult, dxWatchResult
        )

        // Merge results
        mergeSpots(results.0, source: .rbn)
        mergeSpots(results.1, source: .pota)
        mergeSpots(results.2, source: .sota)
        mergeSpots(results.3, source: .wwff)
        mergeSpots(results.4, source: .dxSummit)
        mergeSpots(results.5, source: .dxHeat)
        mergeSpots(results.6, source: .dxWatch)

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

    // MARK: Private

    /// Async second-tier backfill — looks each spotter up via the existing
    /// QRZ+HamDB-backed CallsignInfoCache (1-hour TTL, 200-entry LRU) and
    /// re-upserts the row with grid/lat/lon when a result comes back. Runs
    /// off the actor; failures are swallowed.
    private static func refineSpotters(_ spotters: [SpotterRow], store: QueryStore) async {
        for var spotter in spotters {
            let info = await CallsignInfoCache.shared.lookup(
                callsign: spotter.callsign,
                qsoSummaries: []
            )
            let grid = info.grid
            // QRZCallbookResult has no lat/lon — only HamDB carries them.
            let lat = info.license?.lat.flatMap(Double.init)
            let lon = info.license?.lon.flatMap(Double.init)
            guard grid != nil || lat != nil || lon != nil else {
                continue
            }
            spotter.grid = grid ?? spotter.grid
            spotter.lat = lat ?? spotter.lat
            spotter.lon = lon ?? spotter.lon
            try? await store.upsertSpotter(spotter)
        }
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

    private func fetchDXSummit() async -> [UnifiedSpot] {
        do {
            let dxSpots = try await dxSummitClient.fetchSpots(limit: 50)
            errors.removeValue(forKey: .dxSummit)
            return dxSpots.map { UnifiedSpot.from(dxSummit: $0) }
        } catch {
            errors[.dxSummit] = error.localizedDescription
            return []
        }
    }

    private func fetchDXHeat() async -> [UnifiedSpot] {
        do {
            let dxSpots = try await dxHeatClient.fetchSpots(limit: 50)
            errors.removeValue(forKey: .dxHeat)
            return dxSpots.compactMap { UnifiedSpot.from(dxHeat: $0) }
        } catch {
            errors[.dxHeat] = error.localizedDescription
            return []
        }
    }

    private func fetchDXWatch() async -> [UnifiedSpot] {
        do {
            let response = try await dxWatchClient.fetchSpots(rows: 50)
            errors.removeValue(forKey: .dxWatch)
            return response.spots.map { spot in
                UnifiedSpot.from(dxWatch: spot, callInfo: response.callInfo[spot.dxCall])
            }
        } catch {
            errors[.dxWatch] = error.localizedDescription
            return []
        }
    }

    // MARK: - Merging & Dedup

    private func mergeSpots(_ newSpots: [UnifiedSpot], source _: SpotSource) {
        recordObservations(newSpots)
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

    private func recordObservations(_ newSpots: [UnifiedSpot]) {
        guard let store = QueryFacade.current, !newSpots.isEmpty else {
            return
        }
        let lookup = dxccLookup
        let rows = newSpots.map { spot -> SpotObservationRow in
            let priority = Self.sourcePriority[spot.source] ?? 0
            let dxEntity = lookup?.lookup(spot.callsign)
            return SpotObservationMapper.observationRow(
                from: spot,
                priority: priority,
                dxEntity: dxEntity
            )
        }
        // Tier 1 — CTY prefix lookup. Free, synchronous, gives us
        // dxcc_entity / continent / centroid for every spotter. Good
        // enough for "spots heard by EU skimmers" queries.
        let spotters = newSpots.compactMap { spot -> SpotterRow? in
            let entity = spot.spotter.flatMap { lookup?.lookup($0) }
            return SpotObservationMapper.spotterRow(from: spot, spotterEntity: entity)
        }
        // Tier 2 — HamDB lookup for spotters whose grid we still don't
        // know. Async, networked, cached for an hour by CallsignInfoCache.
        let spottersNeedingHamDB = spotters.filter { $0.grid == nil }
        Task.detached(priority: .utility) {
            do {
                try await store.recordObservations(rows)
                for spotter in spotters {
                    try await store.upsertSpotter(spotter)
                }
            } catch {
                // Best-effort mirror; swallow.
            }
            await Self.refineSpotters(spottersNeedingHamDB, store: store)
        }
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-maxSpotAge)
        unifiedSpots = unifiedSpots.filter { $0.value.timestamp > cutoff }
    }
}
