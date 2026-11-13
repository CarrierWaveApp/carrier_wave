import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QRZCallsignMapping

/// Maps a callsign to its QRZ API key and bookId.
/// Each QRZ API key is 1:1 with a callsign/logbook.
struct QRZCallsignMapping: Codable, Identifiable, Equatable {
    let callsign: String
    let apiKey: String
    let bookId: String?
    var isPrimary: Bool

    var id: String {
        callsign
    }
}

// MARK: - QRZError

enum QRZError: Error, LocalizedError {
    case invalidApiKey(String)
    case subscriptionRequired
    case sessionExpired
    case uploadFailed(String)
    case fetchFailed(String)
    case networkError(Error)
    case invalidResponse(String)
    case noQSOs

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .invalidApiKey(reason):
            "Invalid QRZ API key: \(reason)"
        case .subscriptionRequired:
            "QRZ XML Logbook Data subscription required. Visit shop.qrz.com to subscribe."
        case .sessionExpired:
            "QRZ session expired, please re-authenticate"
        case let .uploadFailed(reason):
            "Upload failed: \(reason)"
        case let .fetchFailed(reason):
            "Fetch failed: \(reason)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(details):
            "Invalid response from QRZ: \(details)"
        case .noQSOs:
            "No QSOs found"
        }
    }
}

// MARK: - QRZStatusResponse

/// Response from QRZ STATUS action
struct QRZStatusResponse {
    let callsign: String
    let bookId: String?
    let qsoCount: Int
    let confirmedCount: Int
}

// MARK: - QRZUploadResult

/// Result of uploading QSOs to QRZ (per-QSO tracking).
/// Uses PersistentIdentifier keys so callers can re-fetch fresh models
/// instead of relying on stale references from before the upload loop.
struct QRZUploadResult {
    let uploaded: Int
    let duplicates: Int
    let failed: Int
    let skipped: Int
    /// PersistentIdentifiers of QSOs confirmed on QRZ
    let confirmedIDs: Set<PersistentIdentifier>
    /// QRZ LOGID for each confirmed QSO, keyed by PersistentIdentifier
    let logIdsByPersistentID: [PersistentIdentifier: String]
}

// MARK: - QRZFetchedQSO

/// A QSO fetched from QRZ logbook
struct QRZFetchedQSO {
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String?
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String? // My park (from MY_SIG_INFO/MY_POTA_REF)
    let theirParkReference: String? // Their park (from SIG_INFO)
    let notes: String?
    let qrzLogId: String?
    let qrzConfirmed: Bool
    let lotwConfirmedDate: Date?
    let dxcc: Int?
    let rawADIF: String
}

// MARK: - QRZSingleUploadOutcome

/// Outcome of uploading a single QSO to QRZ
struct QRZSingleUploadOutcome {
    let uploaded: Int
    let duplicates: Int
    let failed: Int
    let confirmed: Bool
    let logId: String?
}

// MARK: - QRZClient

@MainActor
final class QRZClient {
    // MARK: Internal

    let baseURL = "https://logbook.qrz.com/api"
    let keychain = KeychainHelper.shared
    let userAgent = "CarrierWave/1.0"

    /// Last error from `hasApiKey()` — available for diagnostic logging
    private(set) var apiKeyError: (any Error)?

    // MARK: - Response Parsing

    /// Parse QRZ API response. ADIF field needs special handling as it contains & characters.
    nonisolated static func parseResponse(_ response: String) -> [String: String] {
        var result: [String: String] = [:]

        // Check if there's an ADIF field - it needs special handling
        // The ADIF field contains HTML entities like &lt; which would break normal parsing
        if let adifRange = response.range(of: "ADIF=") {
            // Parse everything before ADIF normally
            let beforeADIF = String(response[..<adifRange.lowerBound])
            for pair in beforeADIF.components(separatedBy: "&") {
                if pair.isEmpty {
                    continue
                }
                let parts = pair.components(separatedBy: "=")
                if parts.count >= 2 {
                    result[parts[0]] = parts.dropFirst().joined(separator: "=")
                }
            }

            // The ADIF value is everything after "ADIF="
            let adifValue = String(response[adifRange.upperBound...])
            result["ADIF"] = adifValue
        } else {
            // No ADIF field, parse normally
            for pair in response.components(separatedBy: "&") {
                let parts = pair.components(separatedBy: "=")
                if parts.count >= 2 {
                    result[parts[0]] = parts.dropFirst().joined(separator: "=")
                }
            }
        }

        return result
    }

    // MARK: - API Key Management

    func saveApiKey(_ key: String) throws {
        try keychain.save(key, for: KeychainHelper.Keys.qrzApiKey)
    }

    func getApiKey() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.qrzApiKey)
    }

    func hasApiKey() -> Bool {
        apiKeyError = nil
        do {
            _ = try keychain.readString(for: KeychainHelper.Keys.qrzApiKey)
            return true
        } catch {
            apiKeyError = error
            return false
        }
    }

    func clearApiKey() {
        try? keychain.delete(for: KeychainHelper.Keys.qrzApiKey)
    }

    func saveCallsign(_ callsign: String) throws {
        try keychain.save(callsign, for: KeychainHelper.Keys.qrzCallsign)
    }

    func getCallsign() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.qrzCallsign)
    }

    // MARK: - BookId Management

    /// Get the stored callsign -> bookId mapping
    func getBookIdMap() -> [String: String] {
        guard let data = try? keychain.read(for: KeychainHelper.Keys.qrzBookIdMap),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return map
    }

    /// Save the callsign -> bookId mapping
    func saveBookIdMap(_ map: [String: String]) throws {
        let data = try JSONEncoder().encode(map)
        try keychain.save(data, for: KeychainHelper.Keys.qrzBookIdMap)
    }

    /// Add or update a bookId for a callsign
    func saveBookId(_ bookId: String, for callsign: String) throws {
        var map = getBookIdMap()
        map[callsign.uppercased()] = bookId
        try saveBookIdMap(map)
    }

    /// Get the bookId for a callsign
    func getBookId(for callsign: String) -> String? {
        getBookIdMap()[callsign.uppercased()]
    }

    // MARK: - API Methods

    /// Validate an API key by calling STATUS action
    func validateApiKey(_ key: String) async throws -> QRZStatusResponse {
        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Form-encode the body
        let formData = [
            "KEY": key,
            "ACTION": "STATUS",
        ]
        request.httpBody = formEncode(formData).data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse("Cannot decode response as UTF-8, \(data.count) bytes")
        }

        let parsed = Self.parseResponse(responseString)

        guard parsed["RESULT"] == "OK" else {
            // AUTH means insufficient privileges (subscription required)
            if parsed["RESULT"] == "AUTH" {
                throw QRZError.subscriptionRequired
            }
            let reason =
                parsed["REASON"]
                    ?? "RESULT=\(parsed["RESULT"] ?? "nil"), response: \(responseString.prefix(200))"
            throw QRZError.invalidApiKey(reason)
        }

        guard let callsign = parsed["CALLSIGN"] else {
            throw QRZError.invalidResponse("No callsign in response: \(responseString.prefix(200))")
        }

        let bookId = parsed["BOOKID"]
        let qsoCount = Int(parsed["COUNT"] ?? "0") ?? 0
        let confirmedCount = Int(parsed["CONFIRMED"] ?? "0") ?? 0

        return QRZStatusResponse(
            callsign: callsign,
            bookId: bookId,
            qsoCount: qsoCount,
            confirmedCount: confirmedCount
        )
    }

    /// Fetch QSOs from QRZ logbook with pagination.
    /// Uses MODSINCE for incremental sync when `since` is provided.
    func fetchQSOs(since: Date? = nil) async throws -> [QRZFetchedQSO] {
        let apiKey = try getApiKey()
        return try await fetchQSOs(apiKey: apiKey, since: since)
    }

    /// Fetch QSOs using a specific API key (for multi-callsign support).
    func fetchQSOs(apiKey: String, since: Date? = nil) async throws -> [QRZFetchedQSO] {
        var allQSOs: [QRZFetchedQSO] = []
        try await paginatedFetch(apiKey: apiKey, since: since) { page in
            allQSOs.append(contentsOf: page)
        }
        return allQSOs
    }

    // MARK: - Sync Timestamps

    /// Get the last successful download date for incremental sync
    func getLastDownloadDate() -> Date? {
        guard
            let dateString = try? keychain.readString(for: KeychainHelper.Keys.qrzLastDownloadDate)
        else {
            return nil
        }
        return ISO8601DateFormatter().date(from: dateString)
    }

    /// Save the last successful download date
    func saveLastDownloadDate(_ date: Date) {
        let dateString = ISO8601DateFormatter().string(from: date)
        try? keychain.save(dateString, for: KeychainHelper.Keys.qrzLastDownloadDate)
    }

    /// Clear the last download date (forces full sync on next run)
    func clearLastDownloadDate() {
        try? keychain.delete(for: KeychainHelper.Keys.qrzLastDownloadDate)
    }

    // MARK: - Session Management

    func logout() {
        clearApiKey()
        clearCallsignMappings()
        try? keychain.delete(for: KeychainHelper.Keys.qrzCallsign)
        try? keychain.delete(for: KeychainHelper.Keys.qrzBookIdMap)
        // Also clear deprecated session-based keys
        try? keychain.delete(for: KeychainHelper.Keys.qrzSessionKey)
        try? keychain.delete(for: KeychainHelper.Keys.qrzUsername)
        // Clear legacy counter keys if they exist
        try? keychain.delete(for: KeychainHelper.Keys.qrzTotalUploaded)
        try? keychain.delete(for: KeychainHelper.Keys.qrzTotalDownloaded)
        try? keychain.delete(for: KeychainHelper.Keys.qrzLastUploadDate)
        try? keychain.delete(for: KeychainHelper.Keys.qrzLastDownloadDate)
    }

    // MARK: Private

    /// Paginated QRZ FETCH with configurable options.
    /// Calls `pageHandler` for each page of results to avoid accumulating full result set.
    private func paginatedFetch(
        apiKey: String, since: Date? = nil, extraOptions: [String] = [],
        pageHandler: ([QRZFetchedQSO]) -> Void
    ) async throws {
        var totalFetched = 0
        var afterLogId: Int64 = 0
        let pageSize = 2_000

        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        while true {
            let request = buildFetchRequest(
                url: url, apiKey: apiKey, afterLogId: afterLogId, pageSize: pageSize,
                since: since, extraOptions: extraOptions
            )
            let (pageQSOs, responseCount) = try await fetchQSOPage(request: request)

            // Find max log_id for pagination
            var maxLogId: Int64 = 0
            for qso in pageQSOs {
                if let logIdStr = qso.qrzLogId, let logId = Int64(logIdStr) {
                    maxLogId = max(maxLogId, logId)
                }
            }

            pageHandler(pageQSOs)
            totalFetched += pageQSOs.count

            NSLog(
                "[QRZ] Pagination: afterLogId=%lld, pageQSOs=%d, responseCount=%d, maxLogId=%lld, total=%d",
                afterLogId, pageQSOs.count, responseCount, maxLogId, totalFetched
            )

            // Use actual parsed QSO count, not API metadata count
            // API COUNT may be inconsistent, causing premature pagination exit
            if pageQSOs.count < pageSize {
                break
            }

            // Can't paginate without log IDs
            if maxLogId == 0 {
                NSLog("[QRZ] WARNING: No log IDs found, cannot continue pagination")
                break
            }

            afterLogId = maxLogId + 1
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        NSLog("[QRZ] Fetch complete: total=%d QSOs", totalFetched)
    }
}

// Upload helper methods are in QRZClient+Upload.swift
// Fetch helper methods are in QRZClient+Fetch.swift
// ADIF helper methods are in QRZClient+ADIF.swift
