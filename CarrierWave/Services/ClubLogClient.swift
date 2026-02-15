import CarrierWaveCore
import Foundation

// MARK: - ClubLogError

enum ClubLogError: Error, LocalizedError {
    case authenticationFailed
    case forbidden
    case uploadFailed(String)
    case uploadRejected(String)
    case fetchFailed(String)
    case networkError(Error)
    case invalidResponse(String)
    case notConfigured
    case serverError(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            "Club Log authentication failed. Check your email and app password."
        case .forbidden:
            "Club Log returned 403 Forbidden. Credentials may be invalid — "
                + "do NOT retry (repeated 403s will get your IP blocked)."
        case let .uploadFailed(reason):
            "Club Log upload failed: \(reason)"
        case let .uploadRejected(reason):
            "Club Log rejected QSO: \(reason)"
        case let .fetchFailed(reason):
            "Club Log fetch failed: \(reason)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(details):
            "Invalid response from Club Log: \(details)"
        case .notConfigured:
            "Club Log is not configured. Add your email and app password in Settings."
        case let .serverError(details):
            "Club Log server error: \(details)"
        }
    }
}

// MARK: - ClubLogFetchedQSO

/// A QSO fetched from Club Log via ADIF download
struct ClubLogFetchedQSO {
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
    let parkReference: String?
    let theirParkReference: String?
    let notes: String?
    let dxcc: Int?
    let rawADIF: String
}

// MARK: - ClubLogUploadResult

struct ClubLogUploadResult {
    let uploaded: Int
    let skipped: Int
}

// MARK: - ClubLogClient

@MainActor
final class ClubLogClient {
    let keychain = KeychainHelper.shared
    let userAgent = "CarrierWave/1.0"

    var isConfigured: Bool {
        hasCredentials() && (try? getApiKey()) != nil
    }

    // MARK: - Credential Management

    func saveCredentials(email: String, password: String, callsign: String) throws {
        try keychain.save(email, for: KeychainHelper.Keys.clublogEmail)
        try keychain.save(password, for: KeychainHelper.Keys.clublogPassword)
        try keychain.save(callsign.uppercased(), for: KeychainHelper.Keys.clublogCallsign)
    }

    func saveApiKey(_ key: String) throws {
        try keychain.save(key, for: KeychainHelper.Keys.clublogApiKey)
    }

    func getApiKey() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.clublogApiKey)
    }

    func getEmail() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.clublogEmail)
    }

    func getPassword() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.clublogPassword)
    }

    func getCallsign() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.clublogCallsign)
    }

    func hasCredentials() -> Bool {
        getEmail() != nil && getPassword() != nil && getCallsign() != nil
    }

    func logout() {
        try? keychain.delete(for: KeychainHelper.Keys.clublogApiKey)
        try? keychain.delete(for: KeychainHelper.Keys.clublogEmail)
        try? keychain.delete(for: KeychainHelper.Keys.clublogPassword)
        try? keychain.delete(for: KeychainHelper.Keys.clublogCallsign)
        try? keychain.delete(for: KeychainHelper.Keys.clublogLastDownloadDate)
    }

    // MARK: - Sync Timestamps

    func getLastDownloadDate() -> Date? {
        guard let dateString = try? keychain.readString(
            for: KeychainHelper.Keys.clublogLastDownloadDate
        ) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: dateString)
    }

    func saveLastDownloadDate(_ date: Date) {
        let dateString = ISO8601DateFormatter().string(from: date)
        try? keychain.save(dateString, for: KeychainHelper.Keys.clublogLastDownloadDate)
    }

    func clearLastDownloadDate() {
        try? keychain.delete(for: KeychainHelper.Keys.clublogLastDownloadDate)
    }

    // MARK: - API Methods

    /// Validate credentials by attempting a small download
    func validateCredentials(
        email: String, password: String, callsign: String
    ) async throws {
        // Test by downloading recent QSOs (last 7 days)
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now)!
        let comps = cal.dateComponents([.year, .month, .day], from: weekAgo)

        var params: [String: String] = [
            "email": email,
            "password": password,
            "call": callsign.uppercased(),
        ]
        if let year = comps.year {
            params["startyear"] = String(year)
        }
        if let month = comps.month {
            params["startmonth"] = String(month)
        }
        if let day = comps.day {
            params["startday"] = String(day)
        }

        let (_, response) = try await performPostRequest(
            url: "https://clublog.org/getadif.php",
            params: params,
            useApiKey: false
        )

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 {
                throw ClubLogError.forbidden
            }
            if httpResponse.statusCode != 200 {
                throw ClubLogError.authenticationFailed
            }
        }
    }

    /// Download QSOs from Club Log as ADIF
    /// - Parameters:
    ///   - since: Optional date to filter (startyear/startmonth/startday)
    func fetchQSOs(since: Date? = nil) async throws -> [ClubLogFetchedQSO] {
        guard let email = getEmail(),
              let password = getPassword(),
              let callsign = getCallsign()
        else {
            throw ClubLogError.notConfigured
        }

        var params: [String: String] = [
            "email": email,
            "password": password,
            "call": callsign,
        ]

        if let since {
            let cal = Calendar(identifier: .gregorian)
            let comps = cal.dateComponents([.year, .month, .day], from: since)
            if let year = comps.year {
                params["startyear"] = String(year)
            }
            if let month = comps.month {
                params["startmonth"] = String(month)
            }
            if let day = comps.day {
                params["startday"] = String(day)
            }
        }

        let (data, response) = try await performPostRequest(
            url: "https://clublog.org/getadif.php",
            params: params,
            useApiKey: false
        )

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
            throw ClubLogError.forbidden
        }

        guard let adifString = String(data: data, encoding: .utf8) else {
            throw ClubLogError.invalidResponse("Cannot decode response as UTF-8")
        }

        // Check for error responses (Club Log returns plain text errors)
        if adifString.lowercased().contains("invalid"), !adifString.contains("<EOH>"),
           !adifString.contains("<eoh>")
        {
            throw ClubLogError.authenticationFailed
        }

        return parseADIFRecords(adifString)
    }

    /// Upload QSOs to Club Log via batch ADIF upload (putlogs.php)
    func uploadQSOs(_ qsos: [QSO]) async throws -> ClubLogUploadResult {
        guard !qsos.isEmpty else {
            return ClubLogUploadResult(uploaded: 0, skipped: 0)
        }

        guard let email = getEmail(),
              let password = getPassword(),
              let callsign = getCallsign()
        else {
            throw ClubLogError.notConfigured
        }

        let apiKey = try getApiKey()
        let accountCallsign = callsign.uppercased()

        // Filter to matching callsign
        let (matchingQSOs, skippedCount) = filterQSOsForUpload(
            qsos, accountCallsign: accountCallsign
        )

        guard !matchingQSOs.isEmpty else {
            return ClubLogUploadResult(uploaded: 0, skipped: skippedCount)
        }

        // Generate ADIF content
        let adifContent = matchingQSOs.map { qso in
            qso.rawADIF ?? generateADIF(for: qso)
        }.joined(separator: "\n")

        // Build multipart form data
        let boundary = UUID().uuidString
        let fields: [String: String] = [
            "email": email,
            "password": password,
            "callsign": accountCallsign,
            "api": apiKey,
        ]

        let body = buildMultipartBody(boundary: boundary, fields: fields, adifContent: adifContent)

        guard let url = URL(string: "https://clublog.org/putlogs.php") else {
            throw ClubLogError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 {
                throw ClubLogError.forbidden
            }
            if httpResponse.statusCode != 200 {
                throw ClubLogError.uploadFailed("HTTP \(httpResponse.statusCode)")
            }
        }

        return ClubLogUploadResult(uploaded: matchingQSOs.count, skipped: skippedCount)
    }

    /// Upload a single QSO in real-time (realtime.php)
    func uploadSingleQSO(_ qso: QSO) async throws {
        guard let email = getEmail(),
              let password = getPassword(),
              let callsign = getCallsign()
        else {
            throw ClubLogError.notConfigured
        }

        let apiKey = try getApiKey()
        let adifRecord = qso.rawADIF ?? generateADIF(for: qso)

        let params: [String: String] = [
            "email": email,
            "password": password,
            "callsign": callsign.uppercased(),
            "api": apiKey,
            "adif": adifRecord,
        ]

        let (data, response) = try await performPostRequest(
            url: "https://clublog.org/realtime.php",
            params: params,
            useApiKey: false,
            contentType: "application/x-www-form-urlencoded"
        )

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 {
                throw ClubLogError.forbidden
            }
            if httpResponse.statusCode == 400 {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ClubLogError.uploadRejected(body)
            }
            if httpResponse.statusCode == 500 {
                throw ClubLogError.serverError("Internal server error — retry later")
            }
        }
    }
}
