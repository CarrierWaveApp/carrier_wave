// Combined spots service for RBN and POTA
//
// Fetches and merges spots from both RBN (Reverse Beacon Network) and
// POTA (Parks on the Air) into a unified format. Enriches spots with
// spotter grid squares from HamDB for map display.

import CarrierWaveData
import Foundation
import SwiftUI

// MARK: - SpotSource

/// Source of a spot
enum SpotSource: Sendable {
    case rbn
    case pota
    case sota
    case wwff
}

// MARK: - UnifiedSpot

/// A spot from either RBN or POTA in a unified format
struct UnifiedSpot: Identifiable, Sendable {
    // MARK: Internal

    let id: String
    let callsign: String
    let frequencyKHz: Double
    let mode: String
    let timestamp: Date
    let source: SpotSource

    // RBN-specific fields
    let snr: Int?
    let wpm: Int?
    let spotter: String?
    var spotterGrid: String?
    var callsignGrid: String? // Grid of the spotted station (for map projection)

    // POTA-specific fields
    let parkRef: String?
    let parkName: String?
    let comments: String?

    // SOTA-specific fields
    var summitCode: String?
    var summitName: String?
    var summitPoints: Int?

    // WWFF-specific fields
    var wwffRef: String?
    var wwffName: String?

    // Location fields
    let locationDesc: String? // POTA raw (e.g., "US-WY")
    var stateAbbr: String? // Parsed state (e.g., "WY") — var for async RBN enrichment

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

    /// Color based on spot freshness
    var ageColor: Color {
        let seconds = Date().timeIntervalSince(timestamp)
        switch seconds {
        case ..<120:
            return .green // < 2 minutes: very fresh
        case ..<600:
            return .blue // 2-10 minutes: recent
        case ..<1_800:
            return .orange // 10-30 minutes: getting stale
        default:
            return .secondary // > 30 minutes: old
        }
    }

    /// Parse US state abbreviation from POTA locationDesc (e.g., "US-WY" → "WY")
    nonisolated static func parseState(from locationDesc: String?) -> String? {
        guard let desc = locationDesc else {
            return nil
        }
        let parts = desc.split(separator: "-")
        guard parts.count >= 2, parts[0] == "US" else {
            return nil
        }
        return String(parts[1])
    }

    /// Check if this spot is a self-spot for the given user callsign
    func isSelfSpot(userCallsign: String) -> Bool {
        let normalizedUser = Self.normalizeCallsign(userCallsign)
        let normalizedSpot = Self.normalizeCallsign(callsign)
        return normalizedUser == normalizedSpot
    }

    // MARK: Private

    /// Normalize callsign by removing portable suffixes and uppercasing
    private static func normalizeCallsign(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        // Remove common portable suffixes: /P, /M, /QRP, /0-9, etc.
        if let slashIndex = upper.firstIndex(of: "/") {
            return String(upper[..<slashIndex])
        }
        return upper
    }
}

// MARK: - GridCache

/// Shared cache for callsign grid lookups with time-based expiration
actor GridCache {
    // MARK: Internal

    static let shared = GridCache()

    /// Get a cached grid if it exists and hasn't expired
    func get(_ callsign: String) -> String?? {
        let key = callsign.uppercased()
        guard let entry = cache[key] else {
            return nil // Not in cache
        }
        if Date().timeIntervalSince(entry.timestamp) > expirationInterval {
            cache.removeValue(forKey: key)
            return nil // Expired
        }
        return entry.grid // Return cached value (may be nil if lookup found nothing)
    }

    /// Store a grid lookup result
    func set(_ callsign: String, grid: String?) {
        let key = callsign.uppercased()
        cache[key] = CacheEntry(grid: grid, timestamp: Date())

        // Prune old entries periodically (when cache gets large)
        if cache.count > 200 {
            pruneExpired()
        }
    }

    // MARK: Private

    /// Cache entry with timestamp
    private struct CacheEntry {
        let grid: String?
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]

    /// Cache entries expire after 1 hour
    private let expirationInterval: TimeInterval = 3_600

    /// Remove expired entries
    private func pruneExpired() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) <= expirationInterval }
    }
}

// MARK: - CallsignStateCache

/// Shared cache for callsign → US state lookups with time-based expiration
actor CallsignStateCache {
    // MARK: Internal

    static let shared = CallsignStateCache()

    /// Get a cached state if it exists and hasn't expired
    func get(_ callsign: String) -> String?? {
        let key = callsign.uppercased()
        guard let entry = cache[key] else {
            return nil // Not in cache
        }
        if Date().timeIntervalSince(entry.timestamp) > expirationInterval {
            cache.removeValue(forKey: key)
            return nil // Expired
        }
        return entry.state // Return cached value (may be nil for non-US)
    }

    /// Store a state lookup result
    func set(_ callsign: String, state: String?) {
        let key = callsign.uppercased()
        cache[key] = CacheEntry(state: state, timestamp: Date())

        if cache.count > 200 {
            pruneExpired()
        }
    }

    // MARK: Private

    private struct CacheEntry {
        let state: String?
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]

    /// Cache entries expire after 1 hour
    private let expirationInterval: TimeInterval = 3_600

    private func pruneExpired() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) <= expirationInterval }
    }
}

// MARK: - SpotsService

/// Service for fetching combined spots from RBN and POTA
actor SpotsService {
    // MARK: Lifecycle

    /// Initialize with pre-created clients from a @MainActor context
    init(rbnClient: RBNClient, potaClient: POTAClient, hamDBClient: HamDBClient = HamDBClient()) {
        self.rbnClient = rbnClient
        self.potaClient = potaClient
        self.hamDBClient = hamDBClient
    }

    // MARK: Internal

    /// Fetch combined spots for a callsign from both RBN and POTA
    /// - Parameters:
    ///   - callsign: The callsign to look up spots for
    ///   - minutes: How many minutes back to search (default 10)
    /// - Returns: Combined and sorted list of spots
    func fetchSpots(for callsign: String, minutes: Int = 10) async throws -> [UnifiedSpot] {
        // Fetch from both sources concurrently (use 1 hour for API, filter locally)
        async let rbnSpots = fetchRBNSpots(for: callsign, hours: 1)
        async let potaSpots = fetchPOTASpots(for: callsign)

        let cutoffDate = Date().addingTimeInterval(-Double(minutes) * 60)

        // Combine results, handling errors gracefully
        var allSpots: [UnifiedSpot] = []

        do {
            try await allSpots.append(contentsOf: rbnSpots)
        } catch {
            // Log but don't fail if RBN is unavailable
            await SyncDebugLog.shared.warning(
                "RBN fetch failed: \(error.localizedDescription)",
                service: .pota
            )
        }

        do {
            try await allSpots.append(contentsOf: potaSpots)
        } catch {
            // Log but don't fail if POTA is unavailable
            await SyncDebugLog.shared.warning(
                "POTA spots fetch failed: \(error.localizedDescription)",
                service: .pota
            )
        }

        // Filter to requested time window
        let filteredSpots = allSpots.filter { $0.timestamp >= cutoffDate }

        // Enrich spots with spotter grid squares from HamDB
        let enrichedSpots = await enrichSpotsWithGrids(filteredSpots)

        // Sort by timestamp, most recent first
        return enrichedSpots.sorted { $0.timestamp > $1.timestamp }
    }

    /// Look up a grid square for a callsign, using the shared cache
    /// - Parameter callsign: The callsign to look up
    /// - Returns: Grid square if found, nil otherwise
    func lookupGrid(for callsign: String) async -> String? {
        let normalized = callsign.uppercased()

        // Check shared cache first
        if let cached = await GridCache.shared.get(normalized) {
            return cached
        }

        // Look up from HamDB
        let grid = try? await hamDBClient.lookup(callsign: normalized)?.grid
        await GridCache.shared.set(normalized, grid: grid)
        return grid
    }

    // MARK: Private

    private let rbnClient: RBNClient
    private let potaClient: POTAClient
    private let hamDBClient: HamDBClient

    /// Maximum number of spotters to look up per request (keeps UI responsive)
    private let maxGridLookups = 15

    /// Look up grids for spotters that don't have them
    private func enrichSpotsWithGrids(_ spots: [UnifiedSpot]) async -> [UnifiedSpot] {
        // Find unique spotters without grids that aren't already cached
        var spottersNeedingGrids: [String] = []
        for spotter in Set(spots.compactMap(\.spotter)) {
            if await GridCache.shared.get(spotter) == nil {
                spottersNeedingGrids.append(spotter)
            }
            if spottersNeedingGrids.count >= maxGridLookups {
                break
            }
        }

        // Look up grids in parallel
        if !spottersNeedingGrids.isEmpty {
            await lookupGrids(for: spottersNeedingGrids)
        }

        // Apply cached grids to spots
        var enrichedSpots: [UnifiedSpot] = []
        for spot in spots {
            var enrichedSpot = spot
            if enrichedSpot.spotterGrid == nil,
               let spotter = spot.spotter,
               let cachedGrid = await GridCache.shared.get(spotter)
            {
                enrichedSpot.spotterGrid = cachedGrid
            }
            enrichedSpots.append(enrichedSpot)
        }
        return enrichedSpots
    }

    /// Look up grids for callsigns in parallel
    private func lookupGrids(for callsigns: [String]) async {
        let client = hamDBClient

        let results = await withTaskGroup(
            of: (String, String?).self,
            returning: [(String, String?)].self
        ) { group in
            for callsign in callsigns {
                group.addTask {
                    let grid = try? await client.lookup(callsign: callsign)?.grid
                    return (callsign, grid)
                }
            }

            var results: [(String, String?)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        for (callsign, grid) in results {
            await GridCache.shared.set(callsign, grid: grid)
        }
    }

    private func fetchRBNSpots(for callsign: String, hours: Int) async throws -> [UnifiedSpot] {
        let spots = try await rbnClient.spots(for: callsign, hours: hours, limit: 50)
        return spots.map { spot in
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

    private func fetchPOTASpots(for callsign: String) async throws -> [UnifiedSpot] {
        let spots = try await potaClient.fetchSpots(for: callsign)
        return spots.compactMap { spot -> UnifiedSpot? in
            guard let freqKHz = spot.frequencyKHz,
                  let timestamp = spot.timestamp
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
}
