// Spot model types
//
// `SpotSource` + `UnifiedSpot` — the app-facing spot model every view and
// persistence path consumes — plus the shared `GridCache`. Spot FETCHING
// moved to the shared Rust engine (`SpotEngineApi`; see SpotEngineProvider
// and FfiSpotAdapters); the old Swift `SpotsService`/`CallsignStateCache`
// fetch-and-enrich machinery was deleted with the Phase 4 swap.

import CarrierWaveData
import Foundation
import SwiftUI

// MARK: - SpotSource

/// Source of a spot
enum SpotSource: CaseIterable {
    case rbn
    case pota
    case sota
    case wwff
    case pskr
    case dxSummit
    case dxHeat
    case dxWatch
    case cluster

    // MARK: Internal

    var displayName: String {
        switch self {
        case .rbn: "RBN"
        case .pota: "POTA"
        case .sota: "SOTA"
        case .wwff: "WWFF"
        case .pskr: "PSKR"
        case .dxSummit: "DX Summit"
        case .dxHeat: "DXHeat"
        case .dxWatch: "DXWatch"
        case .cluster: "Cluster"
        }
    }

    /// Colors follow Sweep's SpotSource where free; pskr already owns purple
    /// on iOS, so dxSummit takes pink instead of Sweep's purple.
    var color: Color {
        switch self {
        case .rbn: .blue
        case .pota: .green
        case .sota: .orange
        case .wwff: .teal
        case .pskr: .purple
        case .dxSummit: .pink
        case .dxHeat: .red
        case .dxWatch: .indigo
        case .cluster: .yellow
        }
    }
}

// MARK: - UnifiedSpot

/// A spot from either RBN or POTA in a unified format
struct UnifiedSpot: Identifiable {
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

    /// Check if this spot is a self-spot (spotter spotted themselves).
    /// Only meaningful for POTA/SOTA/WWFF — RBN spotters are network nodes, never the station itself.
    func isSelfSpot(userCallsign _: String) -> Bool {
        guard let spotter else {
            return false
        }
        let normalizedSpotter = Self.normalizeCallsign(spotter)
        let normalizedCallsign = Self.normalizeCallsign(callsign)
        return normalizedSpotter == normalizedCallsign
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
