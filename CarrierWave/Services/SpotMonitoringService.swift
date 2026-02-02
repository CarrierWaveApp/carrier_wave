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

    /// Stop monitoring spots
    func stopMonitoring() {
        isMonitoring = false
        pollingTask?.cancel()
        pollingTask = nil
        callsign = nil
        myGrid = nil
        myCoordinate = nil
        summary = .empty
        lastError = nil
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
                // RBN only for non-POTA sessions
                if rbnClient == nil {
                    rbnClient = RBNClient()
                }
                let rbnSpots = try await rbnClient!.spots(for: callsign, hours: 1, limit: 50)
                let cutoff = Date().addingTimeInterval(-Double(spotWindowMinutes) * 60)
                spots =
                    rbnSpots
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
                                comments: nil
                            )
                        }
            }

            // Enrich spots with distance and region
            let enrichedSpots = enrichSpots(spots)

            // Build summary
            summary = buildSummary(from: enrichedSpots)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            // Keep existing summary on error
        }
    }

    /// Enrich spots with distance and region information
    private func enrichSpots(_ spots: [UnifiedSpot]) -> [EnrichedSpot] {
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
    private func buildSummary(from spots: [EnrichedSpot]) -> SpotSummary {
        // Group by region
        var byRegion: [SpotRegion: [EnrichedSpot]] = [:]
        for spot in spots {
            byRegion[spot.region, default: []].append(spot)
        }

        // Calculate distance range
        let distances = spots.compactMap(\.distanceMeters)
        let minDistance = distances.min()
        let maxDistance = distances.max()

        return SpotSummary(
            spots: spots,
            byRegion: byRegion,
            minDistanceMeters: minDistance,
            maxDistanceMeters: maxDistance,
            timestamp: Date()
        )
    }

    /// Calculate great-circle distance between two coordinates
    private func calculateDistance(
        from coord1: CLLocationCoordinate2D,
        to coord2: CLLocationCoordinate2D
    ) -> Double {
        let loc1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let loc2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return loc1.distance(from: loc2)
    }
}
