// swiftlint:disable file_length
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
            "Login to QRZ Callbook in Settings → Data"
        case .qrzAuthFailed:
            "Check your QRZ credentials in Settings → Data"
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

    /// Check if any Polo notes sources are configured
    func hasPoloNotesSources() -> Bool {
        let sources = fetchAllSourcesOnMainActor()
        return !sources.isEmpty
    }

    /// Get cached info for a callsign (synchronous, no network)
    /// - Parameter callsign: The callsign to look up
    /// - Returns: CallsignInfo if in cache, nil otherwise
    func cachedInfo(for callsign: String) -> CallsignInfo? {
        cache[callsign.uppercased()]
    }

    /// Preload Polo notes from all sources (clubs and user-configured)
    func preloadPoloNotes() async {
        await loadPoloNotes()
    }

    /// Clear all caches
    func clearCache() {
        cache.removeAll()
        poloNotesCache.removeAll()
        pendingLookups.removeAll()
    }

    // MARK: Private

    // MARK: - Types

    /// Entry from a notes source with source title and optional emoji/note/name
    private struct NotesEntry {
        let title: String
        let emoji: String?
        let note: String?
        let name: String?
    }

    /// A source with its title for tracking
    private struct NotesSource {
        let url: URL
        let title: String
    }

    // MARK: - Private State

    /// Cache of recent lookups
    private var cache: [String: CallsignInfo] = [:]

    /// Order of cache entries for LRU eviction
    private var cacheOrder: [String] = []

    /// Pending lookup tasks (for deduplication) - legacy
    private var pendingLookups: [String: Task<CallsignInfo?, Never>] = [:]

    /// Pending lookup tasks with results (for deduplication)
    private var pendingResultLookups: [String: Task<CallsignLookupResult, Never>] = [:]

    /// Merged Polo notes from all clubs
    private var poloNotesCache: [String: CallsignInfo] = [:]

    /// When Polo notes were last loaded
    private var poloNotesLoadedAt: Date?

    /// ModelContext for accessing Club data
    private let modelContext: ModelContext?

    // MARK: - Polo Notes Lookup

    private func lookupInPoloNotes(_ callsign: String) async -> CallsignInfo? {
        // Reload Polo notes if stale or empty
        if poloNotesCache.isEmpty || isPoloNotesCacheStale() {
            await loadPoloNotes()
        }

        return poloNotesCache[callsign]
    }

    private func isPoloNotesCacheStale() -> Bool {
        guard let loadedAt = poloNotesLoadedAt else {
            return true
        }
        // Refresh every 5 minutes
        return Date().timeIntervalSince(loadedAt) > 300
    }

    private func loadPoloNotes() async {
        // Fetch all sources with titles on main actor (SwiftData requirement)
        let sources = fetchAllSourcesOnMainActor()

        guard !sources.isEmpty else {
            return
        }

        // Load all sources and track entries by source
        var entriesByCallsign: [String: [NotesEntry]] = [:]

        await withTaskGroup(of: (String, [String: CallsignInfo]).self) { group in
            for source in sources {
                group.addTask {
                    let entries = await (try? PoloNotesParser.load(from: source.url)) ?? [:]
                    return (source.title, entries)
                }
            }

            for await (sourceTitle, entries) in group {
                for (callsign, info) in entries {
                    var existing = entriesByCallsign[callsign] ?? []
                    existing.append(
                        NotesEntry(
                            title: sourceTitle,
                            emoji: info.emoji,
                            note: info.note,
                            name: info.name
                        )
                    )
                    entriesByCallsign[callsign] = existing
                }
            }
        }

        // Merge entries into CallsignInfo with all emojis and source titles
        // Sort by source title for consistent ordering (requirement 5)
        var merged: [String: CallsignInfo] = [:]
        for (callsign, entries) in entriesByCallsign {
            let sortedEntries = entries.sorted { $0.title < $1.title }
            let allEmojis = sortedEntries.compactMap(\.emoji).filter { !$0.isEmpty }
            let sourceTitles = sortedEntries.map(\.title)
            // Use first non-nil name and note from sorted entries
            let name = sortedEntries.compactMap(\.name).first
            let note = sortedEntries.compactMap(\.note).first

            merged[callsign] = CallsignInfo(
                callsign: callsign,
                name: name,
                note: note,
                emoji: allEmojis.first,
                source: .poloNotes,
                allEmojis: allEmojis.isEmpty ? nil : allEmojis,
                matchingSources: sourceTitles
            )
        }

        poloNotesCache = merged
        poloNotesLoadedAt = Date()
    }

    private func fetchAllSourcesOnMainActor() -> [NotesSource] {
        guard let context = modelContext else {
            return []
        }

        var sources: [NotesSource] = []

        // Fetch from clubs
        do {
            let clubDescriptor = FetchDescriptor<Club>()
            let clubs = try context.fetch(clubDescriptor)

            for club in clubs {
                if !club.poloNotesListURL.isEmpty,
                   let url = URL(string: club.poloNotesListURL)
                {
                    sources.append(NotesSource(url: url, title: club.name))
                }
            }
        } catch {
            print("[CallsignLookup] Failed to load clubs: \(error)")
        }

        // Fetch from user-configured sources
        do {
            let sourceDescriptor = FetchDescriptor<CallsignNotesSource>(
                predicate: #Predicate { $0.isEnabled }
            )
            let userSources = try context.fetch(sourceDescriptor)

            for source in userSources {
                if let url = URL(string: source.url) {
                    sources.append(NotesSource(url: url, title: source.title))
                }
            }
        } catch {
            print("[CallsignLookup] Failed to load callsign notes sources: \(error)")
        }

        return sources
    }

    // MARK: - Cache Management

    private func updateCache(_ info: CallsignInfo) {
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

// MARK: - QRZ XML API

extension CallsignLookupService {
    /// QRZ XML callbook API base URL
    private static let qrzXMLURL = "https://xmldata.qrz.com/xml/current/"

    /// Look up a callsign in QRZ XML callbook
    /// Uses the logbook API key which also works for XML callbook lookups
    private func lookupInQRZ(_ callsign: String) async -> CallsignInfo? {
        let result = await lookupInQRZWithResult(callsign)
        return result.info
    }

    /// Look up a callsign in QRZ with detailed result/error information
    private func lookupInQRZWithResult(_ callsign: String) async -> CallsignLookupResult {
        // Get Callbook credentials from keychain
        guard
            let username = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookUsername
            ),
            let password = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookPassword
            )
        else {
            return .error(.noQRZApiKey)
        }

        // First, get a session key using username/password
        let sessionResult = await getQRZSessionKeyWithCredentials(
            username: username, password: password
        )
        guard let sessionKey = sessionResult.sessionKey else {
            return .error(sessionResult.error ?? .qrzAuthFailed, qrzAttempted: true)
        }

        // Then look up the callsign
        return await performQRZLookupWithResult(callsign: callsign, sessionKey: sessionKey)
    }

    /// Result from QRZ session key request
    private struct QRZSessionResult {
        let sessionKey: String?
        let error: CallsignLookupError?
    }

    /// Get a QRZ session key with error details using username/password credentials
    private func getQRZSessionKeyWithCredentials(
        username: String, password: String
    ) async -> QRZSessionResult {
        guard var urlComponents = URLComponents(string: Self.qrzXMLURL) else {
            return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
        }

        // QRZ XML API uses username/password authentication
        urlComponents.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "agent", value: "CarrierWave"),
        ]

        guard let url = urlComponents.url else {
            return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
            }

            guard let xmlString = String(data: data, encoding: .utf8) else {
                return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
            }

            // Check for error in response
            if let errorMsg = parseXMLValue(from: xmlString, tag: "Error") {
                if errorMsg.lowercased().contains("invalid")
                    || errorMsg.lowercased().contains("password")
                    || errorMsg.lowercased().contains("username")
                {
                    return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
                }
                return QRZSessionResult(
                    sessionKey: nil, error: .networkError(errorMsg)
                )
            }

            // Parse session key from XML response
            if let key = parseXMLValue(from: xmlString, tag: "Key") {
                return QRZSessionResult(sessionKey: key, error: nil)
            }

            return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
        } catch {
            return QRZSessionResult(
                sessionKey: nil,
                error: .networkError(error.localizedDescription)
            )
        }
    }

    /// Perform the actual callsign lookup with detailed result
    private func performQRZLookupWithResult(
        callsign: String,
        sessionKey: String
    ) async -> CallsignLookupResult {
        guard let url = buildQRZLookupURL(sessionKey: sessionKey, callsign: callsign) else {
            return .error(.networkError("Invalid URL"), qrzAttempted: true)
        }

        do {
            let xmlString = try await fetchQRZResponse(url: url)

            // Check for error
            if let errorMsg = parseXMLValue(from: xmlString, tag: "Error") {
                if errorMsg.lowercased().contains("not found") {
                    return .notFound(qrzAttempted: true, poloNotesChecked: true)
                }
                return .error(.networkError(errorMsg), qrzAttempted: true)
            }

            guard let info = parseCallsignInfoFromXML(xmlString, callsign: callsign) else {
                return .notFound(qrzAttempted: true, poloNotesChecked: true)
            }
            return .fromQRZ(info)
        } catch {
            return .error(.networkError(error.localizedDescription), qrzAttempted: true)
        }
    }

    private func buildQRZLookupURL(sessionKey: String, callsign: String) -> URL? {
        guard var urlComponents = URLComponents(string: Self.qrzXMLURL) else {
            return nil
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "s", value: sessionKey),
            URLQueryItem(name: "callsign", value: callsign),
        ]
        return urlComponents.url
    }

    private func fetchQRZResponse(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw QRZLookupError.httpError
        }

        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw QRZLookupError.invalidResponse
        }

        return xmlString
    }

    private func parseCallsignInfoFromXML(_ xmlString: String, callsign: String) -> CallsignInfo? {
        let firstName = parseXMLValue(from: xmlString, tag: "fname")
        let lastName = parseXMLValue(from: xmlString, tag: "name")
        let nickname = parseXMLValue(from: xmlString, tag: "nickname")
        let name = combineNames(first: firstName, last: lastName)
        let grid = parseXMLValue(from: xmlString, tag: "grid")
        let qth = parseXMLValue(from: xmlString, tag: "addr2")
        let state = parseXMLValue(from: xmlString, tag: "state")
        let country = parseXMLValue(from: xmlString, tag: "country")
        let licenseClass = parseXMLValue(from: xmlString, tag: "class")

        guard name != nil || grid != nil || qth != nil else {
            return nil
        }

        return CallsignInfo(
            callsign: callsign,
            name: name,
            firstName: firstName,
            nickname: nickname,
            qth: qth,
            state: state,
            country: country,
            grid: grid,
            licenseClass: licenseClass,
            source: .qrz
        )
    }

    private enum QRZLookupError: Error {
        case httpError
        case invalidResponse
    }

    /// Get a QRZ session key using username/password credentials
    private func getQRZSessionKey(username: String, password: String) async -> String? {
        guard var urlComponents = URLComponents(string: Self.qrzXMLURL) else {
            return nil
        }

        // QRZ XML API uses username/password authentication
        urlComponents.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
        ]

        guard let url = urlComponents.url else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                return nil
            }

            guard let xmlString = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Parse session key from XML response
            // Format: <Key>SESSION_KEY</Key>
            return parseXMLValue(from: xmlString, tag: "Key")
        } catch {
            return nil
        }
    }

    /// Perform the actual callsign lookup with a session key
    private func performQRZLookup(callsign: String, sessionKey: String) async -> CallsignInfo? {
        guard let url = buildQRZLookupURL(sessionKey: sessionKey, callsign: callsign) else {
            return nil
        }

        do {
            let xmlString = try await fetchQRZResponse(url: url)

            // Check for error
            if xmlString.contains("<Error>") {
                return nil
            }

            return parseCallsignInfoFromXML(xmlString, callsign: callsign)
        } catch {
            return nil
        }
    }

    /// Parse a value from XML by tag name
    private func parseXMLValue(from xml: String, tag: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"

        guard let startRange = xml.range(of: openTag),
              let endRange = xml.range(of: closeTag, range: startRange.upperBound ..< xml.endIndex)
        else {
            return nil
        }

        let value = String(xml[startRange.upperBound ..< endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.isEmpty ? nil : value
    }

    /// Combine first and last name
    private func combineNames(first: String?, last: String?) -> String? {
        if let first, let last {
            "\(first) \(last)"
        } else if let first {
            first
        } else if let last {
            last
        } else {
            nil
        }
    }
}
