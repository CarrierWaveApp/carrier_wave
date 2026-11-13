// Spot Engine Provider
//
// Owns the process-wide Rust `SpotEngineApi` instance: constructs it with
// the user's source configuration, feeds host-side context (user grid +
// callsign, CTY database, needs snapshot), and pauses/resumes the poll loop
// across app lifecycle transitions.
//
// New sources (DX Summit / DXHeat / DXWatch / telnet cluster) ship
// DEFAULT-OFF; toggles live in the hunter spot filter sheet, and the
// cluster additionally needs a node configured in Hunt Settings.

import CarrierWaveCore
import CarrierWaveCwFfi
import CarrierWaveData
import UIKit

@MainActor
@Observable
final class SpotEngineProvider {
    // MARK: Lifecycle

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                SpotEngineProvider.shared.engineIfBuilt?.pause()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                guard let engine = SpotEngineProvider.shared.engineIfBuilt else {
                    return
                }
                engine.resume()
                Task.detached { await engine.refresh() }
            }
        }
    }

    // MARK: Internal

    static let shared = SpotEngineProvider()

    // MARK: - Source configuration (persisted)

    /// Which sources the engine fetches comes from the hunter spot filter
    /// sheet's persisted selection (`hunterSpotFilters`) — one source of
    /// truth for "enabled" — while the cluster node's host/port live here
    /// (config, not enablement). Defaults seed Sweep's first preset (W3LPL).
    static let clusterHostKey = "spotEngineClusterHost"
    static let clusterPortKey = "spotEngineClusterPort"
    static let defaultClusterHost = "w3lpl.net"
    static let defaultClusterPort = 7_373

    var lastEngineError: String?

    /// Error from the most recent band-scope (saved-query filter)
    /// application — shown in the spot filter sheet so a broken query is
    /// visible instead of silently filtering nothing.
    var lastBandScopeQueryError: String?

    private(set) var engineIfBuilt: SpotEngineApi?

    // MARK: - Spots observers (shared listener)

    /// The engine holds ONE listener slot, so the provider owns it and
    /// fans generation updates out to every registered observer (hunter
    /// monitoring, Band Scope, …). The engine runs while at least one
    /// observer is registered and stops when the last one leaves.
    func addSpotsObserver(id: String, onUpdate: @escaping @MainActor () -> Void) {
        spotsObservers[id] = onUpdate
        startEngineIfNeeded()
    }

    func removeSpotsObserver(id: String) {
        spotsObservers.removeValue(forKey: id)
        if spotsObservers.isEmpty, let engine = engineIfBuilt {
            engineStarted = false
            Task.detached { await engine.stop() }
        }
    }

    /// The engine, constructing it on first use. Returns nil only when the
    /// Rust core fails to initialize (recorded in `lastEngineError`).
    func engine() -> SpotEngineApi? {
        if let built = engineIfBuilt {
            return built
        }
        do {
            let engine = try SpotEngineApi(config: currentConfig())
            engineIfBuilt = engine
            feedUserContext()
            feedCTYDatabase()
            feedEnrichmentCachePath()
            return engine
        } catch {
            lastEngineError = error.localizedDescription
            return nil
        }
    }

    /// Recompute + push the engine config (poll cadence matches the app's
    /// existing 2-minute PollingCoordinator rhythm, not Sweep's 30 s).
    func applyConfig() {
        engineIfBuilt?.setConfig(config: currentConfig())
    }

    /// Push the operator's grid + callsign (distance origin, self-spot
    /// detection, `cw_user_*` SQL functions).
    func feedUserContext() {
        let grid = UserDefaults.standard.string(forKey: "myGrid") ?? ""
        let callsign = UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        engineIfBuilt?.setUserContext(grid: grid.isEmpty ? nil : grid, callsign: callsign)
    }

    /// Push the freshest needs snapshot into the engine (fire-and-forget).
    func feedNeedsSnapshot() {
        guard let engine = engineIfBuilt else {
            return
        }
        Task.detached(priority: .utility) {
            let snapshot = await NeedsEngine.shared.snapshot()
            let ffi = await snapshot.ffiSnapshot
            engine.setNeedsSnapshot(snapshot: ffi)
        }
    }

    /// Point the engine at the on-disk enrichment cache so relaunches
    /// don't re-pay HamDB lookups for callsigns seen before. Off-main:
    /// the engine loads the file synchronously when the path is set.
    func feedEnrichmentCachePath() {
        guard let engine = engineIfBuilt else {
            return
        }
        Task.detached(priority: .utility) {
            let manager = FileManager.default
            guard let dir = manager.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else {
                return
            }
            try? manager.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("spot-enrichment-cache.json")
            engine.setEnrichmentCachePath(path: file.path)
        }
    }

    /// Feed the cached CTY.dat content for DXCC resolution.
    func feedCTYDatabase() {
        guard let engine = engineIfBuilt else {
            return
        }
        Task.detached(priority: .utility) {
            guard let content = await CTYService.shared.rawDatabaseContent() else {
                return
            }
            engine.setCtyDatabase(ctyContent: content)
        }
    }

    /// Connect the DX cluster when selected in the spot filter sheet and a
    /// node is configured; disconnect otherwise. Called on start and
    /// whenever the settings change.
    func applyClusterConnection() {
        guard let engine = engineIfBuilt else {
            return
        }
        let defaults = UserDefaults.standard
        let enabled = Self.persistedFilterSources().contains(.cluster)
        let host = defaults.string(forKey: Self.clusterHostKey) ?? Self.defaultClusterHost
        let storedPort = defaults.integer(forKey: Self.clusterPortKey)
        let port = storedPort > 0 ? storedPort : Self.defaultClusterPort
        let callsign = defaults.string(forKey: "loggerDefaultCallsign") ?? ""
        Task.detached {
            if enabled, !host.isEmpty, !callsign.isEmpty {
                await engine.connectCluster(
                    host: host, port: UInt16(clamping: port), loginCallsign: callsign
                )
            } else {
                await engine.disconnectCluster()
            }
        }
    }

    /// Apply (or clear) the hunter filter sheet's "Filter by saved query"
    /// selection as the engine's band-scope allow-list query. Mirrors
    /// Sweep's `bandScopeFilterMode`: the query's `spot_id` result set
    /// drives `allowed_spot_ids` in every snapshot. On any failure the
    /// query is cleared so the Swift widget-filter path stays
    /// authoritative (never a silently-broken filter).
    func applyBandScopeQuery() {
        guard let engine = engineIfBuilt else {
            return
        }
        let queryID = Self.persistedFilters().savedQueryID
        Task.detached(priority: .utility) {
            var sql: String?
            var resolveError: String?
            if let queryID {
                let store = SavedQueryStores.makeStore()
                let queries = await (try? store.list()) ?? []
                sql = queries.first { $0.id == queryID }?.sql
                if sql == nil {
                    resolveError = "Saved query not found — showing all spots."
                }
            }
            var applyError = resolveError
            do {
                try engine.setBandScopeQuery(sql: sql)
            } catch {
                if case let SpotQueryError.Query(reason, line, _) = error {
                    applyError = line.map { "Query invalid (line \($0)): \(reason)" }
                        ?? "Query invalid: \(reason)"
                } else {
                    applyError = "Query invalid: \(error.localizedDescription)"
                }
                // Fall back to widget filtering: clear the broken query so
                // snapshots stop carrying a stale allow-list.
                do {
                    try engine.setBandScopeQuery(sql: nil)
                } catch {
                    // Clearing failed too — the error above is still what
                    // the user needs to see.
                }
            }
            let message = applyError
            await MainActor.run {
                SpotEngineProvider.shared.lastBandScopeQueryError = message
            }
        }
    }

    // MARK: Private

    /// Shared engine listener: hops to the main actor and fans out to the
    /// observer registry. Callbacks arrive on Rust worker threads.
    private final class BroadcastListener: SpotEngineListener {
        // MARK: Lifecycle

        init(onUpdate: @escaping @Sendable () -> Void) {
            self.onUpdate = onUpdate
        }

        // MARK: Internal

        let onUpdate: @Sendable () -> Void

        func onSpotsUpdated(generation _: UInt64) {
            onUpdate()
        }

        func onClusterLine(line _: String) {
            // iOS has no cluster terminal view; lines are consumed as spots.
        }

        func onClusterState(connected _: Bool) {}
    }

    private var spotsObservers: [String: @MainActor () -> Void] = [:]
    private var broadcastListener: BroadcastListener?
    private var engineStarted = false

    /// The spot filter sheet's persisted state — the single source of
    /// truth for enabled sources and the saved-query filter selection.
    private static func persistedFilters() -> SpotFilters {
        guard let raw = UserDefaults.standard.string(forKey: "hunterSpotFilters"),
              let filters = SpotFilters(rawValue: raw)
        else {
            return SpotFilters()
        }
        return filters
    }

    /// The spot filter sheet's persisted source selection.
    private static func persistedFilterSources() -> Set<SpotFilters.SourceFilter> {
        persistedFilters().sources
    }

    private func startEngineIfNeeded() {
        guard !engineStarted, let engine = engine() else {
            return
        }
        engineStarted = true
        let listener = BroadcastListener {
            Task { @MainActor in
                for handler in SpotEngineProvider.shared.spotsObservers.values {
                    handler()
                }
            }
        }
        broadcastListener = listener
        Task.detached {
            await engine.start(listener: listener)
        }
    }

    /// Enabled poll sources = the hunter feed's classic five, plus any of
    /// the DX-web trio the user selected in the filter sheet. Cluster rides
    /// its own connection, not the poll loop.
    private func currentConfig() -> FfiSpotEngineConfig {
        var sources: [FfiSpotSource] = [.rbn, .pota, .sota, .wwff, .pskr]
        let selected = Self.persistedFilterSources()
        if selected.contains(.dxSummit) {
            sources.append(.dxSummit)
        }
        if selected.contains(.dxHeat) {
            sources.append(.dxHeat)
        }
        if selected.contains(.dxWatch) {
            sources.append(.dxWatch)
        }
        let rbnLimit = UInt32(SpotFetchLimits.huntRBN)
        let sotaCount = UInt32(SpotFetchLimits.huntSOTA)
        return FfiSpotEngineConfig(
            activitiesBaseUrl: "https://activities.carrierwave.app",
            enabledSources: sources,
            pollIntervalSecs: 120,
            maxSpotAgeSecs: 1_800,
            rbnLimit: rbnLimit,
            sotaCount: sotaCount,
            dxWebLimit: 50
        )
    }
}
