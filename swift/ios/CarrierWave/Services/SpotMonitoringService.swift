// Spot Monitoring Service
//
// Thin adapter over the shared Rust spot engine (`SpotEngineApi`).
// The engine owns fetching all sources, merge/dedup/prune, enrichment,
// and needs matching; this service keeps the app-facing contract every
// existing consumer relies on — `summary`, `hunterSpots`, `needsSummary`,
// the `onSpotsReceived` persistence callback, and the friend/needs
// notifiers + widget updates.
//
// Hunter mode drives the engine's poll loop via a listener; activator
// mode polls the engine's one-shot per-callsign fetch (server-side RBN
// `call=` filter) on the existing PollingCoordinator cadence.

import CarrierWaveCore
import CarrierWaveCwFfi
import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - SpotMonitoringService

/// Service that monitors spots in the background during logging sessions
@MainActor
@Observable
final class SpotMonitoringService {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Current spot summary (updated every polling interval)
    private(set) var summary: SpotSummary = .empty

    /// Whether monitoring is active
    private(set) var isMonitoring = false

    /// Last error message (cleared on successful fetch)
    private(set) var lastError: String?

    /// Callback fired when new enriched spots are received (for persistence)
    var onSpotsReceived: (([EnrichedSpot]) -> Void)?

    /// Friend spot notifier — fires toasts and local notifications for friend spots
    let friendNotifier = FriendSpotNotifier()

    /// Needs spot notifier — fires toasts for spots matching operator needs
    let needsNotifier = NeedsSpotNotifier()

    /// Current needs-on-air summary (updated each poll cycle)
    private(set) var needsSummary: NeedsOnAirSummary = .empty

    /// Whether in hunter mode (fetches ALL spots, not just self-spots)
    private(set) var isHunterMode = false

    /// All spots in hunter mode (full list for display)
    private(set) var hunterSpots: [EnrichedSpot] = []

    /// True after the first hunter-mode fetch completes (success or empty result),
    /// so the UI can distinguish "still loading" from "loaded, no spots right now".
    private(set) var hasFetchedHunterSpots = false

    /// Result of the engine's active band-scope (saved-query) filter —
    /// spot ids allowed through when "Filter by saved query" is on.
    /// nil when no query is active (or the last one failed validation).
    private(set) var allowedSpotIds: Set<String>?

    /// When the engine last completed a poll (nil = never this session).
    private(set) var lastRefresh: Date?

    /// Start monitoring spots for a callsign (activator mode).
    /// - Parameters:
    ///   - callsign: The operator's callsign to monitor spots for
    ///   - myGrid: The operator's grid square for distance calculation
    ///   - includePOTA: Whether to include POTA spots (for POTA activations)
    func startMonitoring(callsign: String, myGrid: String?, includePOTA: Bool) {
        guard !isMonitoring else {
            return
        }

        self.callsign = callsign.uppercased()
        self.includePOTA = includePOTA
        isMonitoring = true
        lastError = nil
        SpotEngineProvider.shared.feedUserContext()

        PollingCoordinator.shared.register(
            id: "spotMonitoring",
            every: 2,
            fireImmediately: true
        ) { [weak self] in
            guard let self, let callsign = self.callsign else {
                return
            }
            await fetchActivatorSpots(for: callsign)
        }
    }

    /// Start monitoring ALL spots for hunter mode (activity log).
    /// - Parameter myGrid: The operator's grid square for distance calculation
    func startHunterMonitoring(myGrid _: String?) {
        guard !isMonitoring else {
            return
        }

        isHunterMode = true
        isMonitoring = true
        lastError = nil

        let provider = SpotEngineProvider.shared
        guard provider.engine() != nil else {
            lastError = provider.lastEngineError
            return
        }
        provider.applyConfig()
        provider.feedUserContext()
        provider.feedCTYDatabase()
        provider.feedNeedsSnapshot()
        provider.applyClusterConnection()
        provider.applyBandScopeQuery()

        provider.addSpotsObserver(id: Self.observerID) { [weak self] in
            self?.consumeEngineSnapshot()
        }
    }

    /// Stop monitoring spots
    func stopMonitoring() {
        if isHunterMode {
            SpotEngineProvider.shared.removeSpotsObserver(id: Self.observerID)
        } else {
            PollingCoordinator.shared.unregister(id: "spotMonitoring")
        }
        isMonitoring = false
        isHunterMode = false
        callsign = nil
        summary = .empty
        hunterSpots = []
        hasFetchedHunterSpots = false
        allowedSpotIds = nil
        lastError = nil
        onSpotsReceived = nil
    }

    /// Force an immediate refresh
    func refresh() async {
        guard isMonitoring else {
            return
        }
        if isHunterMode {
            if let engine = SpotEngineProvider.shared.engineIfBuilt {
                await engine.refresh()
            }
        } else if let callsign {
            await fetchActivatorSpots(for: callsign)
        }
    }

    /// Consume a fresh engine publish (hunter mode): read the snapshot,
    /// convert, and run the notification/persistence pipeline.
    func consumeEngineSnapshot() {
        guard isHunterMode,
              let engine = SpotEngineProvider.shared.engineIfBuilt
        else {
            return
        }
        let snapshot = engine.snapshot(filter: nil, worked: nil)
        let enriched = snapshot.spots.map(\.appEnrichedSpot)

        hunterSpots = enriched
        allowedSpotIds = snapshot.allowedSpotIds.map(Set.init)
        hasFetchedHunterSpots = true
        if snapshot.lastRefresh > 0 {
            lastRefresh = Date(timeIntervalSince1970: TimeInterval(snapshot.lastRefresh))
        }
        summary = buildSummary(from: enriched)
        needsSummary = SpotNeedsMatcher.summarize(enriched)
        lastError = nil

        friendNotifier.checkSpots(enriched)
        needsNotifier.checkSpots(enriched)
        NeedsWidgetWriter.update(spots: enriched)
        onSpotsReceived?(enriched)
    }

    func buildSummary(from spots: [EnrichedSpot]) -> SpotSummary {
        var byRegion: [SpotRegion: [EnrichedSpot]] = [:]
        for spot in spots {
            byRegion[spot.region, default: []].append(spot)
        }
        let distances = spots.compactMap(\.distanceMeters)
        return SpotSummary(
            spots: spots,
            byRegion: byRegion,
            minDistanceMeters: distances.min(),
            maxDistanceMeters: distances.max(),
            timestamp: Date()
        )
    }

    // MARK: Private

    /// Observer id in `SpotEngineProvider`'s shared-listener registry.
    private static let observerID = "hunterMonitoring"

    /// Window for spots (10 minutes)
    private let spotWindowMinutes: UInt32 = 10

    /// Current callsign being monitored
    private var callsign: String?

    /// Whether to include POTA spots
    private var includePOTA = false

    /// Fetch per-callsign spots (activator mode) via the engine's one-shot
    /// path and update the summary.
    private func fetchActivatorSpots(for callsign: String) async {
        let provider = SpotEngineProvider.shared
        guard let engine = provider.engine() else {
            lastError = provider.lastEngineError
            return
        }
        do {
            let ffiSpots = try await engine.fetchCallsignSpots(
                callsign: callsign,
                minutes: spotWindowMinutes,
                includePota: includePOTA
            )
            let enriched = ffiSpots.map(\.appEnrichedSpot)
            summary = buildSummary(from: enriched)
            lastError = nil
            friendNotifier.checkSpots(enriched)
            onSpotsReceived?(enriched)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
