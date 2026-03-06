import Foundation

// MARK: - PreviousQSOSummary

/// Lightweight summary of a previous QSO, extracted on MainActor before passing to the cache actor.
struct PreviousQSOSummary: Sendable {
    let timestamp: Date
    let band: String
    let mode: String
    let notes: String?
}

// MARK: - CallsignInfo

/// Combined callsign information from HamDB lookup and local QSO history.
struct CallsignInfo: Sendable {
    let callsign: String
    let license: HamDBLicense?
    let previousQSOs: [PreviousQSOSummary]

    var previousQSOCount: Int {
        previousQSOs.count
    }

    var lastWorked: Date? {
        previousQSOs.first?.timestamp
    }

    var lastBand: String? {
        previousQSOs.first?.band
    }

    var lastMode: String? {
        previousQSOs.first?.mode
    }

    var lastNotes: String? {
        previousQSOs.first?.notes
    }

    var operatorName: String? {
        license?.fullName
    }

    var licenseClass: String? {
        license?.class
    }

    var grid: String? {
        license?.grid
    }

    var location: String? {
        let parts = [license?.city, license?.state, license?.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - CallsignInfoCache

/// Actor-based cache for callsign information combining HamDB lookups with local QSO history.
/// Follows the GridCache pattern: 1-hour TTL, 200 max entries, auto-pruning.
actor CallsignInfoCache {
    // MARK: Internal

    static let shared = CallsignInfoCache()

    /// Look up callsign info, using cache if available.
    /// Caller provides pre-fetched QSO summaries (extracted on MainActor before calling).
    func lookup(
        callsign: String,
        qsoSummaries: [PreviousQSOSummary]
    ) async -> CallsignInfo {
        let key = callsign.uppercased()

        // Check cache (only HamDB portion is cached; QSO summaries are always fresh)
        let cachedLicense: HamDBLicense?
        if let entry = cache[key], Date().timeIntervalSince(entry.timestamp) <= expirationInterval {
            cachedLicense = entry.license
        } else {
            // Fetch from HamDB
            cachedLicense = try? await hamDBClient.lookup(callsign: key)
            cache[key] = CacheEntry(license: cachedLicense, timestamp: Date())

            if cache.count > maxEntries {
                pruneExpired()
            }
        }

        return CallsignInfo(
            callsign: key,
            license: cachedLicense,
            previousQSOs: qsoSummaries
        )
    }

    // MARK: Private

    private struct CacheEntry {
        let license: HamDBLicense?
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let hamDBClient = HamDBClient()
    private let expirationInterval: TimeInterval = 3_600
    private let maxEntries = 200

    private func pruneExpired() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) <= expirationInterval }
    }
}
