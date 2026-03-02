// Spot Monitoring Service
//
// Manages background polling of RBN and POTA spots during active logging sessions.
// Enriches spots with distance and region information for summary display.

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

    /// Whether in hunter mode (fetches ALL spots, not just self-spots)
    private(set) var isHunterMode = false

    /// All spots in hunter mode (full list for display)
    private(set) var hunterSpots: [EnrichedSpot] = []

    /// Start monitoring spots for a callsign
    /// - Parameters:
    ///   - callsign: The operator's callsign to monitor spots for
    ///   - myGrid: The operator's grid square for distance calculation
    ///   - includePOTA: Whether to include POTA spots (for POTA activations)
    func startMonitoring(callsign: String, myGrid: String?, includePOTA: Bool) {
        guard !isMonitoring else {
            return
        }

        self.callsign = callsign.uppercased()
        self.myGrid = myGrid
        self.includePOTA = includePOTA

        // Calculate operator's coordinate for distance calculations
        if let grid = myGrid {
            myCoordinate = MaidenheadConverter.coordinate(from: grid)
        } else {
            myCoordinate = nil
        }

        isMonitoring = true
        lastError = nil

        // Start polling task
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    /// Start monitoring ALL spots for hunter mode (activity log)
    /// - Parameter myGrid: The operator's grid square for distance calculation
    func startHunterMonitoring(myGrid: String?) {
        guard !isMonitoring else {
            return
        }

        self.myGrid = myGrid
        isHunterMode = true

        if let grid = myGrid {
            myCoordinate = MaidenheadConverter.coordinate(from: grid)
        } else {
            myCoordinate = nil
        }

        isMonitoring = true
        lastError = nil

        pollingTask = Task { [weak self] in
            await self?.hunterPollLoop()
        }
    }

    /// Stop monitoring spots
    func stopMonitoring() {
        isMonitoring = false
        isHunterMode = false
        pollingTask?.cancel()
        pollingTask = nil
        callsign = nil
        myGrid = nil
        myCoordinate = nil
        summary = .empty
        hunterSpots = []
        lastError = nil
        onSpotsReceived = nil
    }

    /// Force an immediate refresh
    func refresh() async {
        guard isMonitoring, let callsign else {
            return
        }
        await fetchSpots(for: callsign)
    }

    // MARK: Private

    /// Polling interval in seconds
    private let pollingInterval: TimeInterval = 45

    /// Window for spots (10 minutes)
    private let spotWindowMinutes = 10

    /// Current callsign being monitored
    private var callsign: String?

    /// Operator's grid square
    private var myGrid: String?

    /// Operator's coordinate (derived from grid)
    private var myCoordinate: CLLocationCoordinate2D?

    /// Whether to include POTA spots
    private var includePOTA = false

    /// Background polling task
    private var pollingTask: Task<Void, Never>?

    /// Spots service for fetching data
    @ObservationIgnored
    private var spotsService: SpotsService?

    /// RBN-only client for non-POTA sessions
    @ObservationIgnored
    private var rbnClient: RBNClient?

    /// SOTA client for hunter mode
    @ObservationIgnored
    private var sotaClient: SOTAClient?

    /// Window for hunter spots (30 minutes — broader than activator mode)
    private let hunterSpotWindowMinutes = 30

    /// Maximum HamDB lookups per poll cycle (keeps 45s refresh fast)
    private let maxStateLookups = 10

    /// Main polling loop
    private func pollLoop() async {
        guard let callsign else {
            return
        }

        // Initial fetch
        await fetchSpots(for: callsign)

        // Polling loop
        while !Task.isCancelled, isMonitoring {
            try? await Task.sleep(for: .seconds(pollingInterval))

            guard !Task.isCancelled, isMonitoring else {
                break
            }

            await fetchSpots(for: callsign)
        }
    }

    /// Hunter mode polling loop — fetches ALL spots
    private func hunterPollLoop() async {
        await fetchAllSpots()

        while !Task.isCancelled, isMonitoring {
            try? await Task.sleep(for: .seconds(pollingInterval))

            guard !Task.isCancelled, isMonitoring else {
                break
            }

            await fetchAllSpots()
        }
    }

    /// Fetch ALL spots for hunter mode (RBN + POTA + SOTA, not filtered by callsign)
    private func fetchAllSpots() async {
        let cutoff = Date().addingTimeInterval(-Double(hunterSpotWindowMinutes) * 60)

        async let rbnUnified = fetchHunterRBNSpots(since: cutoff)
        async let potaUnified = fetchHunterPOTASpots(since: cutoff)
        async let sotaUnified = fetchHunterSOTASpots(since: cutoff)

        var allSpots = await rbnUnified + potaUnified + sotaUnified
        allSpots.sort { $0.timestamp > $1.timestamp }

        // Show spots immediately (before slow HamDB enrichment)
        let quickEnriched = enrichSpots(allSpots)
        hunterSpots = quickEnriched
        summary = buildSummary(from: quickEnriched)
        lastError = nil

        // Enrich RBN spots with state from HamDB (may be slow)
        let stateEnriched = await enrichWithStates(allSpots)
        let enriched = enrichSpots(stateEnriched)
        hunterSpots = enriched
        summary = buildSummary(from: enriched)

        // Check for friend spots
        friendNotifier.checkSpots(enriched)

        // Notify listener for persistence
        onSpotsReceived?(enriched)
    }

    /// Fetch all RBN spots (not per-callsign) for hunter mode
    private func fetchHunterRBNSpots(since cutoff: Date) async -> [UnifiedSpot] {
        let client = RBNClient()
        guard let rbnSpots = try? await client.spots(since: cutoff, limit: 200) else {
            return []
        }
        return rbnSpots.map { spot in
            UnifiedSpot(
                id: "rbn-\(spot.id)",
                callsign: spot.callsign,
                frequencyKHz: spot.frequency,
                mode: spot.mode,
                timestamp: spot.timestamp,
                source: .rbn,
                snr: spot.snr,
                wpm: spot.wpm,
                spotter: spot.spotter,
                spotterGrid: spot.spotterGrid,
                parkRef: nil,
                parkName: nil,
                comments: nil,
                summitCode: nil,
                summitName: nil,
                summitPoints: nil,
                locationDesc: nil,
                stateAbbr: nil
            )
        }
    }

    /// Fetch all POTA spots for hunter mode
    private func fetchHunterPOTASpots(since cutoff: Date) async -> [UnifiedSpot] {
        let client = POTAClient(authService: POTAAuthService())
        guard let potaSpots = try? await client.fetchActiveSpots() else {
            return []
        }
        return potaSpots.compactMap { spot in
            guard let freqKHz = spot.frequencyKHz,
                  let timestamp = spot.timestamp,
                  timestamp >= cutoff
            else {
                return nil
            }
            return UnifiedSpot(
                id: "pota-\(spot.spotId)",
                callsign: spot.activator,
                frequencyKHz: freqKHz,
                mode: spot.mode,
                timestamp: timestamp,
                source: .pota,
                snr: nil,
                wpm: nil,
                spotter: spot.spotter,
                spotterGrid: nil,
                parkRef: spot.reference,
                parkName: spot.parkName,
                comments: spot.comments,
                summitCode: nil,
                summitName: nil,
                summitPoints: nil,
                locationDesc: spot.locationDesc,
                stateAbbr: UnifiedSpot.parseState(from: spot.locationDesc)
            )
        }
    }

    /// Fetch all SOTA spots for hunter mode
    private func fetchHunterSOTASpots(since cutoff: Date) async -> [UnifiedSpot] {
        if sotaClient == nil {
            sotaClient = SOTAClient()
        }
        guard let sotaSpots = try? await sotaClient!.fetchSpots(count: 50) else {
            return []
        }
        return sotaSpots.compactMap { spot in
            guard let freqKHz = spot.frequencyKHz,
                  let timestamp = spot.parsedTimestamp,
                  timestamp >= cutoff
            else {
                return nil
            }
            return UnifiedSpot(
                id: "sota-\(spot.id)",
                callsign: spot.activatorCallsign,
                frequencyKHz: freqKHz,
                mode: spot.mode.uppercased(),
                timestamp: timestamp,
                source: .sota,
                snr: nil,
                wpm: nil,
                spotter: spot.spotterCallsign,
                spotterGrid: nil,
                parkRef: nil,
                parkName: nil,
                comments: spot.comments,
                summitCode: spot.fullSummitReference,
                summitName: spot.summitName,
                summitPoints: spot.points,
                locationDesc: nil,
                stateAbbr: nil
            )
        }
    }

    /// Fetch spots and update summary
    private func fetchSpots(for callsign: String) async {
        do {
            let spots: [UnifiedSpot]

            if includePOTA {
                // Use combined service for POTA activations
                if spotsService == nil {
                    spotsService = SpotsService(
                        rbnClient: RBNClient(),
                        potaClient: POTAClient(authService: POTAAuthService())
                    )
                }
                spots = try await spotsService!.fetchSpots(
                    for: callsign, minutes: spotWindowMinutes
                )
            } else {
                spots = try await fetchActivatorRBNSpots(for: callsign)
            }

            let enrichedSpots = enrichSpots(spots)
            summary = buildSummary(from: enrichedSpots)
            lastError = nil
            friendNotifier.checkSpots(enrichedSpots)
            onSpotsReceived?(enrichedSpots)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Fetch RBN-only spots for a specific callsign (activator mode, non-POTA)
    private func fetchActivatorRBNSpots(for callsign: String) async throws -> [UnifiedSpot] {
        if rbnClient == nil {
            rbnClient = RBNClient()
        }
        let rbnSpots = try await rbnClient!.spots(for: callsign, hours: 1, limit: 50)
        let cutoff = Date().addingTimeInterval(-Double(spotWindowMinutes) * 60)
        return rbnSpots
            .filter { $0.timestamp >= cutoff }
            .map { spot in
                UnifiedSpot(
                    id: "rbn-\(spot.id)",
                    callsign: spot.callsign,
                    frequencyKHz: spot.frequency,
                    mode: spot.mode,
                    timestamp: spot.timestamp,
                    source: .rbn,
                    snr: spot.snr,
                    wpm: spot.wpm,
                    spotter: spot.spotter,
                    spotterGrid: spot.spotterGrid,
                    parkRef: nil,
                    parkName: nil,
                    comments: nil,
                    summitCode: nil,
                    summitName: nil,
                    summitPoints: nil,
                    locationDesc: nil,
                    stateAbbr: nil
                )
            }
    }
}

// MARK: - SpotMonitoringService + Enrichment

@MainActor
private extension SpotMonitoringService {
    /// Enrich RBN spots with US state from HamDB callsign lookup
    func enrichWithStates(_ spots: [UnifiedSpot]) async -> [UnifiedSpot] {
        let hamDB = HamDBClient()
        var lookupCount = 0

        var result: [UnifiedSpot] = []
        for var spot in spots {
            // POTA and SOTA spots don't need HamDB state lookups
            if spot.source == .pota || spot.source == .sota {
                result.append(spot)
                continue
            }

            // Check cache first
            if let cached = await CallsignStateCache.shared.get(spot.callsign) {
                spot.stateAbbr = cached
                result.append(spot)
                continue
            }

            // Limit lookups per cycle
            guard lookupCount < maxStateLookups else {
                result.append(spot)
                continue
            }

            // Look up from HamDB
            let state = try? await hamDB.lookup(callsign: spot.callsign)?.state
            await CallsignStateCache.shared.set(spot.callsign, state: state)
            spot.stateAbbr = state
            lookupCount += 1
            result.append(spot)
        }
        return result
    }

    /// Enrich spots with distance and region information
    func enrichSpots(_ spots: [UnifiedSpot]) -> [EnrichedSpot] {
        spots.map { spot in
            let spotterCoord: CLLocationCoordinate2D? =
                if let grid = spot.spotterGrid {
                    MaidenheadConverter.coordinate(from: grid)
                } else {
                    nil
                }

            let distance: Double? =
                if let myCoord = myCoordinate, let spotterCoord {
                    calculateDistance(from: myCoord, to: spotterCoord)
                } else {
                    nil
                }

            let region = SpotRegion.from(grid: spot.spotterGrid)

            return EnrichedSpot(
                spot: spot,
                distanceMeters: distance,
                region: region
            )
        }
    }

    /// Build a summary from enriched spots
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

    /// Calculate great-circle distance between two coordinates
    func calculateDistance(
        from coord1: CLLocationCoordinate2D,
        to coord2: CLLocationCoordinate2D
    ) -> Double {
        let loc1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let loc2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return loc1.distance(from: loc2)
    }
}
