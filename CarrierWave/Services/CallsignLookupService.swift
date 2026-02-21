import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - CallsignLookupError

/// Errors that can occur during callsign lookup
enum CallsignLookupError: LocalizedError, Equatable, Sendable {
    /// No QRZ API key configured
    case noQRZApiKey
    /// QRZ session authentication failed
    case qrzAuthFailed
    /// Network request failed
    case networkError(String)
    /// Callsign not found in any source
    case notFound
    /// No lookup sources configured (no Polo notes, no QRZ key)
    case noSourcesConfigured

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noQRZApiKey:
            "QRZ Callbook not configured"
        case .qrzAuthFailed:
            "QRZ authentication failed"
        case let .networkError(message):
            "Network error: \(message)"
        case .notFound:
            "Callsign not found"
        case .noSourcesConfigured:
            "No lookup sources configured"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noQRZApiKey:
            "Login to QRZ Callbook in Settings -> Data"
        case .qrzAuthFailed:
            "Check your QRZ credentials in Settings -> Data"
        case .networkError:
            "Check your internet connection"
        case .notFound:
            nil
        case .noSourcesConfigured:
            "Configure QRZ Callbook or Polo Notes in Settings"
        }
    }
}

// MARK: - CallsignLookupResult

/// Result of a callsign lookup with detailed status
struct CallsignLookupResult: Equatable, Sendable {
    /// The callsign info if found
    let info: CallsignInfo?
    /// Error if lookup failed (nil if found or still searching)
    let error: CallsignLookupError?
    /// Whether QRZ lookup was attempted
    let qrzAttempted: Bool
    /// Whether Polo notes were checked
    let poloNotesChecked: Bool

    /// Whether any info was found
    nonisolated var found: Bool {
        info != nil
    }

    /// Create a successful result
    nonisolated static func success(_ info: CallsignInfo) -> CallsignLookupResult {
        CallsignLookupResult(info: info, error: nil, qrzAttempted: false, poloNotesChecked: true)
    }

    /// Create a result from QRZ lookup
    nonisolated static func fromQRZ(_ info: CallsignInfo) -> CallsignLookupResult {
        CallsignLookupResult(info: info, error: nil, qrzAttempted: true, poloNotesChecked: true)
    }

    /// Create a not found result
    nonisolated static func notFound(qrzAttempted: Bool, poloNotesChecked: Bool)
        -> CallsignLookupResult
    {
        CallsignLookupResult(
            info: nil,
            error: .notFound,
            qrzAttempted: qrzAttempted,
            poloNotesChecked: poloNotesChecked
        )
    }

    /// Create an error result
    nonisolated static func error(
        _ error: CallsignLookupError,
        qrzAttempted: Bool = false,
        poloNotesChecked: Bool = false
    ) -> CallsignLookupResult {
        CallsignLookupResult(
            info: nil,
            error: error,
            qrzAttempted: qrzAttempted,
            poloNotesChecked: poloNotesChecked
        )
    }
}

// MARK: - CallsignLookupService

/// Service for looking up callsign information from multiple sources.
/// Uses a two-tier lookup strategy:
/// 1. Polo notes lists (local, fast, offline-capable)
/// 2. QRZ XML callbook API (remote, comprehensive)
@MainActor
final class CallsignLookupService {
    // MARK: Lifecycle

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: Internal

    // MARK: - Configuration

    /// Maximum entries to keep in cache
    let maxCacheSize = 100

    /// Debounce delay for lookups (seconds)
    let debounceDelay: TimeInterval = 0.5

    /// Maximum age for cached entries before refresh (seconds)
    let maxCacheAge: TimeInterval = 3_600

    // MARK: - Private State

    /// Cache of recent lookups (QRZ results)
    var cache: [String: CallsignInfo] = [:]

    /// Order of cache entries for LRU eviction
    var cacheOrder: [String] = []

    /// Pending lookup tasks (for deduplication) - legacy
    var pendingLookups: [String: Task<CallsignInfo?, Never>] = [:]

    /// Pending lookup tasks with results (for deduplication)
    var pendingResultLookups: [String: Task<CallsignLookupResult, Never>] = [:]

    /// ModelContext for accessing Club data (used by CallsignNotesCache)
    let modelContext: ModelContext?

    // MARK: - Public API

    /// Look up a callsign, checking Polo notes first, then QRZ
    /// - Parameter callsign: The callsign to look up
    /// - Returns: CallsignInfo if found, nil otherwise
    func lookup(_ callsign: String) async -> CallsignInfo? {
        let result = await lookupWithResult(callsign)
        return result.info
    }

    /// Look up a callsign with detailed result information
    /// - Parameter callsign: The callsign to look up
    /// - Returns: CallsignLookupResult with info and/or error details
    func lookupWithResult(_ callsign: String) async -> CallsignLookupResult {
        let normalizedCallsign = callsign.uppercased()

        // Check cache first
        if let cached = cache[normalizedCallsign], cached.age < maxCacheAge {
            return .success(cached)
        }

        // Check pending lookups
        if let pending = pendingResultLookups[normalizedCallsign] {
            return await pending.value
        }

        // Start new lookup
        let task = Task<CallsignLookupResult, Never> {
            // Debounce
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            // Tier 1: Polo notes (local)
            let poloInfo = await lookupInPoloNotes(normalizedCallsign)

            // Tier 2: QRZ XML API (remote) - always try if credentials configured
            let qrzResult = await lookupInQRZWithResult(normalizedCallsign)

            // Merge results: Polo Notes emoji/note + QRZ name/grid/location
            if let polo = poloInfo, let qrz = qrzResult.info {
                let merged = CallsignInfo(
                    callsign: normalizedCallsign,
                    name: qrz.name,
                    firstName: qrz.firstName,
                    nickname: qrz.nickname,
                    note: polo.note,
                    emoji: polo.emoji,
                    qth: qrz.qth,
                    state: qrz.state,
                    country: qrz.country,
                    grid: qrz.grid,
                    licenseClass: qrz.licenseClass,
                    source: .qrz, // Primary source is QRZ for name/grid
                    allEmojis: polo.allEmojis,
                    matchingSources: polo.matchingSources
                )
                updateCache(merged)
                return .fromQRZ(merged)
            }

            // QRZ only (no Polo Notes match)
            if let info = qrzResult.info {
                updateCache(info)
                return .fromQRZ(info)
            }

            // Polo Notes only (QRZ not configured or lookup failed)
            if let info = poloInfo {
                updateCache(info)
                return .success(info)
            }

            // Return error from QRZ attempt, or not found
            if let error = qrzResult.error {
                return .error(error, qrzAttempted: true, poloNotesChecked: true)
            }

            return .notFound(qrzAttempted: true, poloNotesChecked: true)
        }

        pendingResultLookups[normalizedCallsign] = task
        let result = await task.value
        pendingResultLookups[normalizedCallsign] = nil

        return result
    }

    /// Check if QRZ Callbook credentials are configured
    func hasQRZCallbookCredentials() -> Bool {
        (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.qrzCallbookUsername)) != nil
            && (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookPassword
            )) != nil
    }

    /// Legacy: Check if QRZ API key is configured (for backward compatibility)
    func hasQRZApiKey() -> Bool {
        hasQRZCallbookCredentials()
    }

    /// Check if any Polo notes sources are configured (based on cached data)
    func hasPoloNotesSources() -> Bool {
        guard let context = modelContext else {
            return false
        }
        let clubCount = (try? context.fetchCount(FetchDescriptor<Club>())) ?? 0
        let sourceCount =
            (try? context.fetchCount(
                FetchDescriptor<CallsignNotesSource>(
                    predicate: #Predicate { $0.isEnabled }
                )
            )) ?? 0
        return clubCount > 0 || sourceCount > 0
    }

    /// Get cached info for a callsign (synchronous, no network)
    func cachedInfo(for callsign: String) -> CallsignInfo? {
        cache[callsign.uppercased()]
    }

    /// Preload Polo notes from all sources (clubs and user-configured)
    func preloadPoloNotes() async {
        guard let context = modelContext else {
            return
        }
        let sources = NotesSourceInfo.fetchAll(modelContext: context)
        await CallsignNotesCache.shared.ensureLoaded(sources: sources)
    }

    /// Clear all caches
    func clearCache() {
        cache.removeAll()
        pendingLookups.removeAll()
    }

    // MARK: - Polo Notes Lookup

    func lookupInPoloNotes(_ callsign: String) async -> CallsignInfo? {
        await CallsignNotesCache.shared.info(for: callsign)
    }

    // MARK: - Cache Management

    func updateCache(_ info: CallsignInfo) {
        let callsign = info.callsign

        // Update cache
        cache[callsign] = info

        // Update LRU order
        if let index = cacheOrder.firstIndex(of: callsign) {
            cacheOrder.remove(at: index)
        }
        cacheOrder.append(callsign)

        // Evict old entries if needed
        while cacheOrder.count > maxCacheSize {
            if let oldest = cacheOrder.first {
                cacheOrder.removeFirst()
                cache.removeValue(forKey: oldest)
            }
        }
    }
}
