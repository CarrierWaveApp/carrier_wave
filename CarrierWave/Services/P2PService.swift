// P2P (Park-to-Park) discovery service
//
// Finds park-to-park opportunities by cross-referencing POTA activator spots
// with RBN spots. This helps activators find other activators they can work
// for P2P credit.

import CoreLocation
import Foundation

// MARK: - P2POpportunity

/// A park-to-park opportunity combining POTA and RBN data
struct P2POpportunity: Identifiable, Sendable {
    let id: String
    let callsign: String
    let frequencyKHz: Double
    let mode: String
    let snr: Int
    let timestamp: Date
    let spotter: String
    let spotterGrid: String
    let parkRef: String
    let parkName: String?
    let locationDesc: String?

    /// Frequency in MHz
    var frequencyMHz: Double {
        frequencyKHz / 1_000.0
    }

    /// Band derived from frequency
    var band: String {
        LoggingSession.bandForFrequency(frequencyMHz)
    }

    /// Formatted frequency string
    var formattedFrequency: String {
        String(format: "%.1f kHz", frequencyKHz)
    }

    /// Time ago string
    var timeAgo: String {
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        } else {
            return "\(Int(seconds / 3_600))h ago"
        }
    }
}

// MARK: - P2PError

enum P2PError: Error, LocalizedError {
    case noGrid
    case notPOTASession
    case noOpportunities

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noGrid:
            "Set your grid in session settings to find nearby P2P opportunities"
        case .notPOTASession:
            "P2P is only available during POTA activations"
        case .noOpportunities:
            "No P2P opportunities right now"
        }
    }
}

// MARK: - P2PProgress

/// Progress updates during P2P discovery
enum P2PProgress: Sendable {
    case fetchingPOTASpots
    case queryingRBN(current: Int, total: Int)
    case filteringByDistance
    case complete
}

// MARK: - P2PService

/// Service for discovering park-to-park opportunities
actor P2PService {
    // MARK: Lifecycle

    init(rbnClient: RBNClient, potaClient: POTAClient, hamDBClient: HamDBClient = HamDBClient()) {
        self.rbnClient = rbnClient
        self.potaClient = potaClient
        self.hamDBClient = hamDBClient
    }

    // MARK: Internal

    /// Maximum distance in meters for "nearby" spotters (1000km for better coverage)
    static let maxDistanceMeters: Double = 1_000_000

    /// Maximum number of POTA activators to query RBN for
    static let maxActivatorsToQuery = 20

    /// Maximum number of spotter grids to look up
    static let maxGridLookups = 15

    /// Find P2P opportunities for a user at a given grid location
    /// - Parameters:
    ///   - userGrid: The user's Maidenhead grid square
    ///   - userCallsign: The user's callsign (to exclude self-spots)
    ///   - onProgress: Progress callback for UI updates
    /// - Returns: List of P2P opportunities sorted by SNR then age
    func findOpportunities(
        userGrid: String,
        userCallsign: String,
        onProgress: (@Sendable (P2PProgress) -> Void)? = nil
    ) async throws -> [P2POpportunity] {
        // Convert user grid to coordinates
        guard let userCoord = MaidenheadConverter.coordinate(from: userGrid) else {
            throw P2PError.noGrid
        }

        // Step 1: Fetch POTA activator spots
        onProgress?(.fetchingPOTASpots)
        let potaSpots = try await potaClient.fetchActiveSpots()

        // Build lookup of POTA activators (callsign -> spot info)
        let activatorLookup = buildActivatorLookup(potaSpots, excludeCallsign: userCallsign)

        if activatorLookup.isEmpty {
            throw P2PError.noOpportunities
        }

        // Step 2: Query RBN for spots of POTA activators
        let activatorsToQuery = Array(activatorLookup.keys.prefix(Self.maxActivatorsToQuery))
        var allRBNSpots: [RBNSpot] = []

        for (index, callsign) in activatorsToQuery.enumerated() {
            onProgress?(.queryingRBN(current: index + 1, total: activatorsToQuery.count))

            do {
                let spots = try await rbnClient.spots(for: callsign, hours: 1, limit: 20)
                allRBNSpots.append(contentsOf: spots)
            } catch {
                // Continue even if one query fails
                continue
            }
        }

        if allRBNSpots.isEmpty {
            throw P2PError.noOpportunities
        }

        // Step 3: Look up grids for spotters and filter by distance
        onProgress?(.filteringByDistance)
        let nearbySpots = await filterSpotsByDistance(
            allRBNSpots,
            userCoord: userCoord,
            maxDistance: Self.maxDistanceMeters
        )

        // Step 4: Build opportunities from nearby spots
        let opportunities = buildOpportunities(
            rbnSpots: nearbySpots,
            activatorLookup: activatorLookup
        )

        onProgress?(.complete)

        if opportunities.isEmpty {
            throw P2PError.noOpportunities
        }

        // Sort by SNR (highest first), then by timestamp (newest first)
        return opportunities.sorted { lhs, rhs in
            if lhs.snr != rhs.snr {
                return lhs.snr > rhs.snr
            }
            return lhs.timestamp > rhs.timestamp
        }
    }

    // MARK: Private

    private let rbnClient: RBNClient
    private let potaClient: POTAClient
    private let hamDBClient: HamDBClient

    /// Build a lookup table of POTA activators
    private func buildActivatorLookup(
        _ spots: [POTASpot],
        excludeCallsign: String
    ) -> [String: POTASpot] {
        var lookup: [String: POTASpot] = [:]
        let excludeNormalized = normalizeCallsign(excludeCallsign)

        for spot in spots {
            let normalized = normalizeCallsign(spot.activator)
            // Exclude user's own callsign
            if normalized == excludeNormalized {
                continue
            }
            // Keep the most recent spot for each callsign
            if let existing = lookup[normalized] {
                if let spotTime = spot.timestamp,
                   let existingTime = existing.timestamp,
                   spotTime > existingTime
                {
                    lookup[normalized] = spot
                }
            } else {
                lookup[normalized] = spot
            }
        }

        return lookup
    }

    /// Filter RBN spots to those from spotters within maxDistance of user
    private func filterSpotsByDistance(
        _ spots: [RBNSpot],
        userCoord: CLLocationCoordinate2D,
        maxDistance: Double
    ) async -> [(spot: RBNSpot, spotterGrid: String)] {
        // Get unique spotters
        let uniqueSpotters = Array(Set(spots.map(\.spotter)).prefix(Self.maxGridLookups))

        // Look up grids for spotters
        var spotterGrids: [String: String] = [:]

        for spotter in uniqueSpotters {
            // Check cache first
            if let cached = await GridCache.shared.get(spotter) {
                if let grid = cached {
                    spotterGrids[spotter] = grid
                }
                continue
            }

            // Look up from HamDB
            if let info = try? await hamDBClient.lookup(callsign: spotter),
               let grid = info.grid
            {
                await GridCache.shared.set(spotter, grid: grid)
                spotterGrids[spotter] = grid
            } else {
                await GridCache.shared.set(spotter, grid: nil)
            }
        }

        // Filter spots by distance
        var nearbySpots: [(spot: RBNSpot, spotterGrid: String)] = []

        for spot in spots {
            guard let grid = spotterGrids[spot.spotter],
                  let spotterCoord = MaidenheadConverter.coordinate(from: grid)
            else {
                continue
            }

            let distance = calculateDistance(from: userCoord, to: spotterCoord)
            if distance <= maxDistance {
                nearbySpots.append((spot: spot, spotterGrid: grid))
            }
        }

        return nearbySpots
    }

    /// Build opportunities from RBN spots and POTA activator data
    private func buildOpportunities(
        rbnSpots: [(spot: RBNSpot, spotterGrid: String)],
        activatorLookup: [String: POTASpot]
    ) -> [P2POpportunity] {
        var opportunities: [P2POpportunity] = []
        var seenCallsigns: Set<String> = []

        for (rbnSpot, spotterGrid) in rbnSpots {
            let normalizedCallsign = normalizeCallsign(rbnSpot.callsign)

            // Skip if we already have this callsign (take first/best)
            if seenCallsigns.contains(normalizedCallsign) {
                continue
            }

            // Get POTA spot info
            guard let potaSpot = activatorLookup[normalizedCallsign] else {
                continue
            }

            let opportunity = P2POpportunity(
                id: "p2p-\(rbnSpot.id)",
                callsign: rbnSpot.callsign,
                frequencyKHz: rbnSpot.frequency,
                mode: rbnSpot.mode,
                snr: rbnSpot.snr,
                timestamp: rbnSpot.timestamp,
                spotter: rbnSpot.spotter,
                spotterGrid: spotterGrid,
                parkRef: potaSpot.reference,
                parkName: potaSpot.parkName,
                locationDesc: potaSpot.locationDesc
            )

            opportunities.append(opportunity)
            seenCallsigns.insert(normalizedCallsign)
        }

        return opportunities
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

    /// Normalize callsign by removing portable suffixes
    private func normalizeCallsign(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        if let slashIndex = upper.firstIndex(of: "/") {
            return String(upper[..<slashIndex])
        }
        return upper
    }
}
