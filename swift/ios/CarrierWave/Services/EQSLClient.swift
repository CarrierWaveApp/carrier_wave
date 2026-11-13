import CarrierWaveData
import Foundation

// MARK: - EQSLError

enum EQSLError: Error, LocalizedError {
    case authenticationFailed
    case uploadFailed(String)
    case uploadRejected(String)
    case fetchFailed(String)
    case networkError(Error)
    case invalidResponse(String)
    case notConfigured

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            "eQSL authentication failed. Check your username and password."
        case let .uploadFailed(reason):
            "eQSL upload failed: \(reason)"
        case let .uploadRejected(reason):
            "eQSL rejected QSO: \(reason)"
        case let .fetchFailed(reason):
            "eQSL fetch failed: \(reason)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(details):
            "Invalid response from eQSL: \(details)"
        case .notConfigured:
            "eQSL is not configured. Add your username and password in Settings."
        }
    }
}

// MARK: - EQSLFetchedQSO

/// A QSO fetched from eQSL via ADIF download
struct EQSLFetchedQSO {
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
    let qslReceived: Bool
    let qslReceivedDate: Date?
    let rawADIF: String
}

// MARK: - EQSLUploadResult

struct EQSLUploadResult {
    let uploaded: Int
    let rejected: Int
    let duplicates: Int
}

// MARK: - EQSLClient

@MainActor
final class EQSLClient {
    let keychain = KeychainHelper.shared
    let userAgent = "CarrierWave/1.0"

    let baseURL = "https://www.eqsl.cc/qslcard"

    // MARK: - Configuration

    var isConfigured: Bool {
        hasCredentials()
    }

    // MARK: - Credential Management

    func saveCredentials(username: String, password: String) throws {
        try keychain.save(username, for: KeychainHelper.Keys.eqslUsername)
        try keychain.save(password, for: KeychainHelper.Keys.eqslPassword)
    }

    func getCredentials() throws -> (username: String, password: String) {
        let username = try keychain.readString(
            for: KeychainHelper.Keys.eqslUsername
        )
        let password = try keychain.readString(
            for: KeychainHelper.Keys.eqslPassword
        )
        return (username, password)
    }

    func hasCredentials() -> Bool {
        do {
            _ = try getCredentials()
            return true
        } catch {
            return false
        }
    }

    func clearCredentials() {
        try? keychain.delete(for: KeychainHelper.Keys.eqslUsername)
        try? keychain.delete(for: KeychainHelper.Keys.eqslPassword)
        try? keychain.delete(for: KeychainHelper.Keys.eqslLastDownloadDate)
    }

    // MARK: - Sync Timestamps

    func getLastDownloadDate() -> Date? {
        guard let dateString = try? keychain.readString(
            for: KeychainHelper.Keys.eqslLastDownloadDate
        ) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: dateString)
    }

    func saveLastDownloadDate(_ date: Date) {
        let dateString = ISO8601DateFormatter().string(from: date)
        try? keychain.save(
            dateString, for: KeychainHelper.Keys.eqslLastDownloadDate
        )
    }

    // MARK: - API Methods

    /// Validate credentials by attempting to fetch inbox
    func testCredentials(
        username: String, password: String
    ) async throws {
        let urlString = "\(baseURL)/DownloadInBox.cfm"
            + "?UserName=\(urlEncode(username))"
            + "&Password=\(urlEncode(password))"
            + "&RcvdSince=20250101"

        guard let url = URL(string: urlString) else {
            throw EQSLError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let response = String(data: data, encoding: .utf8) else {
            throw EQSLError.invalidResponse("Cannot decode response")
        }

        if response.lowercased().contains("error: no match on username") {
            throw EQSLError.authenticationFailed
        }
        if response.lowercased().contains("error: incorrect password") {
            throw EQSLError.authenticationFailed
        }
    }

    /// Download confirmed QSOs (inbox) from eQSL
    func fetchQSOs(since: Date? = nil) async throws -> [EQSLFetchedQSO] {
        let credentials = try getCredentials()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let sinceStr = dateFormatter.string(
            from: since ?? Date(timeIntervalSince1970: 0)
        )

        let urlString = "\(baseURL)/DownloadInBox.cfm"
            + "?UserName=\(urlEncode(credentials.username))"
            + "&Password=\(urlEncode(credentials.password))"
            + "&RcvdSince=\(sinceStr)"
            + "&ConfirmedOnly=1"

        guard let url = URL(string: urlString) else {
            throw EQSLError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw EQSLError.networkError(error)
        }

        guard let responseStr = String(data: data, encoding: .utf8) else {
            throw EQSLError.invalidResponse("Cannot decode response")
        }

        if responseStr.lowercased().contains("error:") {
            if responseStr.lowercased().contains("no match on username")
                || responseStr.lowercased().contains("incorrect password")
            {
                throw EQSLError.authenticationFailed
            }
            // "Your InBox is empty" is not an error
            if responseStr.lowercased().contains("inbox is empty") {
                return []
            }
            throw EQSLError.fetchFailed(String(responseStr.prefix(200)))
        }

        return parseADIFRecords(responseStr)
    }

    /// Upload QSOs to eQSL via ADIF
    func uploadQSOs(_ qsos: [QSO]) async throws -> EQSLUploadResult {
        guard !qsos.isEmpty else {
            return EQSLUploadResult(uploaded: 0, rejected: 0, duplicates: 0)
        }

        let credentials = try getCredentials()

        let adifContent = buildADIFForUpload(qsos)

        let urlString = "\(baseURL)/ImportADIF.cfm"
        guard let url = URL(string: urlString) else {
            throw EQSLError.invalidResponse("Invalid URL")
        }

        let boundary = UUID().uuidString
        var body = Data()

        // Username field
        appendFormField(&body, boundary: boundary, name: "eqsl_user",
                        value: credentials.username)
        // Password field
        appendFormField(&body, boundary: boundary, name: "eqsl_pswd",
                        value: credentials.password)
        // ADIF file
        appendFileField(&body, boundary: boundary, name: "Ession",
                        filename: "upload.adi", content: adifContent)
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw EQSLError.networkError(error)
        }

        guard let responseStr = String(data: data, encoding: .utf8) else {
            throw EQSLError.invalidResponse("Cannot decode response")
        }

        return parseUploadResponse(responseStr, totalQSOs: qsos.count)
    }
}
