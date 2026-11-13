import CarrierWaveCore
import Foundation

// MARK: - PreviousQSOSummary

/// Lightweight summary of a previous QSO, extracted on MainActor before passing to the cache actor.
struct PreviousQSOSummary {
    let timestamp: Date
    let band: String
    let mode: String
    let notes: String?
}

// MARK: - CallsignInfoSource

/// Where the callsign data came from
enum CallsignInfoSource {
    case qrz
    case hamdb
}

// MARK: - CallsignInfo

/// Combined callsign information from QRZ, HamDB, local QSO history, and Polo notes.
struct CallsignInfo {
    let callsign: String
    let license: HamDBLicense?
    let qrzResult: QRZCallbookResult?
    let previousQSOs: [PreviousQSOSummary]
    let components: CallsignComponents?
    var qrzError: String?
    var poloEmoji: String?
    var poloName: String?
    var poloNote: String?
    var poloSources: [String]?

    /// Primary data source (QRZ preferred over HamDB)
    var source: CallsignInfoSource? {
        if qrzResult != nil {
            return .qrz
        }
        if license != nil {
            return .hamdb
        }
        return nil
    }

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

    /// Operator name — QRZ preferred, then HamDB. Normalized to title case.
    var operatorName: String? {
        (qrzResult?.name ?? license?.fullName)?.capitalized
    }

    /// License class — QRZ preferred, then HamDB
    var licenseClass: String? {
        qrzResult?.licenseClass ?? license?.class
    }

    /// Grid square — QRZ preferred, then HamDB
    var grid: String? {
        qrzResult?.grid ?? license?.grid
    }

    /// Location string — QRZ preferred, then HamDB
    var location: String? {
        let city = qrzResult?.city ?? license?.city
        let st = qrzResult?.state ?? license?.state
        let ctry = qrzResult?.country ?? license?.country
        let parts = [city, st, ctry]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Previous callsign (QRZ only)
    var previousCallsign: String? {
        qrzResult?.previousCallsign
    }

    /// Note when QRZ redirected to a different callsign
    var callsignChangeNote: String? {
        qrzResult?.callsignChangeNote
    }
}

// MARK: - CallsignInfoCache

/// Actor-based cache for callsign information combining QRZ callbook,
/// HamDB lookups, and local QSO history.
/// Follows the GridCache pattern: 1-hour TTL, 200 max entries, auto-pruning.
actor CallsignInfoCache {
    // MARK: Internal

    static let shared = CallsignInfoCache()

    /// Look up callsign info, using cache if available.
    /// Tries QRZ first (if credentials configured), falls back to HamDB.
    /// Parses prefix/suffix modifiers and looks up the base callsign.
    /// Caller provides pre-fetched QSO summaries (extracted on MainActor before calling).
    func lookup(
        callsign: String,
        qsoSummaries: [PreviousQSOSummary],
        components: CallsignComponents? = nil
    ) async -> CallsignInfo {
        let key = callsign.uppercased()
        let lookupKey = components?.baseCallsign ?? key

        // Check cache — only use if at least one source returned data.
        // Don't cache double-nil results (both QRZ and HamDB failed).
        if let entry = cache[lookupKey],
           Date().timeIntervalSince(entry.timestamp) <= expirationInterval,
           entry.qrzResult != nil || entry.license != nil
        {
            return CallsignInfo(
                callsign: key,
                license: entry.license,
                qrzResult: entry.qrzResult,
                previousQSOs: qsoSummaries,
                components: components
            )
        }

        // Fetch from QRZ and HamDB in parallel using the base callsign
        async let qrzTask = qrzClient.lookup(callsign: lookupKey)
        async let hamdbTask = fetchHamDB(lookupKey)

        let qrzResult = await qrzTask
        let hamdbLicense = await hamdbTask
        let qrzErr = await qrzClient.lastError

        cache[lookupKey] = CacheEntry(
            license: hamdbLicense,
            qrzResult: qrzResult,
            timestamp: Date()
        )

        if cache.count > maxEntries {
            pruneExpired()
        }

        return CallsignInfo(
            callsign: key,
            license: hamdbLicense,
            qrzResult: qrzResult,
            previousQSOs: qsoSummaries,
            components: components,
            qrzError: qrzErr
        )
    }

    // MARK: Private

    private struct CacheEntry {
        let license: HamDBLicense?
        let qrzResult: QRZCallbookResult?
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let hamDBClient = HamDBClient()
    private let qrzClient = QRZCallbookClient()
    private let expirationInterval: TimeInterval = 3_600
    private let maxEntries = 200

    private func fetchHamDB(_ callsign: String) async -> HamDBLicense? {
        try? await hamDBClient.lookup(callsign: callsign)
    }

    private func pruneExpired() {
        let now = Date()
        cache = cache.filter {
            now.timeIntervalSince($0.value.timestamp) <= expirationInterval
        }
    }
}
