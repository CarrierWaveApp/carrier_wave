import CarrierWaveData
import Foundation

@MainActor
final class HAMRSClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    // MARK: - Configuration

    var isConfigured: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.hamrsApiKey)) != nil
    }

    func hasApiKey() -> Bool {
        isConfigured
    }

    func getApiKey() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.hamrsApiKey)
    }

    // MARK: - Setup

    /// Configure HAMRS with API key
    /// Validates the key before saving by calling the auth endpoint
    func configure(apiKey: String) async throws {
        // Validate by attempting to authenticate
        let authResponse = try await authenticate(with: apiKey)

        guard authResponse.subscribed else {
            throw HAMRSError.subscriptionInactive
        }

        guard let urlString = authResponse.url, let url = URL(string: urlString) else {
            throw HAMRSError.invalidCouchDBURL
        }

        // Save the API key only after successful validation
        try keychain.save(apiKey, for: KeychainHelper.Keys.hamrsApiKey)

        // Cache the CouchDB URL
        couchDBURL = url
    }

    /// Clear all HAMRS credentials
    func clearCredentials() {
        try? keychain.delete(for: KeychainHelper.Keys.hamrsApiKey)
        couchDBURL = nil
    }

    // MARK: - Fetch QSOs

    /// Fetch all QSOs from HAMRS, joined with their logbook info
    func fetchAllQSOs() async throws -> [(HAMRSQSO, HAMRSLogbook)] {
        let couchURL = try await ensureCouchDBURL()

        // Fetch logbooks and QSOs in parallel
        async let logbooksTask = fetchLogbooks(from: couchURL)
        async let qsosTask = fetchQSOs(from: couchURL)

        let logbooks = try await logbooksTask
        let qsos = try await qsosTask

        // Build logbook lookup by ID
        var logbookById: [String: HAMRSLogbook] = [:]
        for logbook in logbooks {
            logbookById[logbook.logbookId] = logbook
        }

        // Join QSOs with their logbooks
        var results: [(HAMRSQSO, HAMRSLogbook)] = []
        for qso in qsos {
            guard let logbookId = qso.logbookId,
                  let logbook = logbookById[logbookId]
            else {
                // QSO without matching logbook - use empty logbook
                let emptyLogbook = HAMRSLogbook(
                    id: "LOGBOOK:unknown",
                    rev: nil,
                    title: nil,
                    createdAt: nil,
                    updatedAt: nil,
                    template: nil,
                    myPark: nil,
                    myGridsquare: nil,
                    operatorCall: nil
                )
                results.append((qso, emptyLogbook))
                continue
            }
            results.append((qso, logbook))
        }

        return results
    }

    // MARK: Private

    private let hamrsBaseURL = "https://hamrs.app"
    private let keychain = KeychainHelper.shared
    private let session: URLSession

    /// Cached CouchDB URL (contains embedded auth credentials)
    private var couchDBURL: URL?

    // MARK: - Authentication

    /// Authenticate with HAMRS and get CouchDB URL
    private func authenticate(with apiKey: String) async throws -> HAMRSAuthResponse {
        guard let url = URL(string: "\(hamrsBaseURL)/api/v1/couchdb_url") else {
            throw HAMRSError.invalidResponse("Invalid auth URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HAMRSError.invalidResponse("Not an HTTP response")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(HAMRSAuthResponse.self, from: data)
            } catch {
                throw HAMRSError.decodingError(error)
            }
        case 401:
            throw HAMRSError.invalidApiKey
        default:
            throw HAMRSError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }
    }

    /// Get cached CouchDB URL or fetch fresh one
    private func ensureCouchDBURL() async throws -> URL {
        if let cached = couchDBURL {
            return cached
        }

        guard let apiKey = try? keychain.readString(for: KeychainHelper.Keys.hamrsApiKey) else {
            throw HAMRSError.notConfigured
        }

        let authResponse = try await authenticate(with: apiKey)

        guard authResponse.subscribed else {
            throw HAMRSError.subscriptionInactive
        }

        guard let urlString = authResponse.url, let url = URL(string: urlString) else {
            throw HAMRSError.invalidCouchDBURL
        }

        couchDBURL = url
        return url
    }

    /// Extract Basic Auth header from URL with embedded credentials
    private func basicAuthHeader(from url: URL) -> String? {
        guard let user = url.user, let password = url.password else {
            return nil
        }
        let credentials = "\(user):\(password)"
        guard let data = credentials.data(using: .utf8) else {
            return nil
        }
        return "Basic \(data.base64EncodedString())"
    }

    /// Remove credentials from URL (for use in requests after extracting auth)
    private func urlWithoutCredentials(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        return components?.url ?? url
    }

    /// Fetch all logbooks from CouchDB
    private func fetchLogbooks(from couchURL: URL) async throws -> [HAMRSLogbook] {
        let url =
            couchURL
                .appendingPathComponent("_all_docs")
                .appending(queryItems: [
                    URLQueryItem(name: "include_docs", value: "true"),
                    URLQueryItem(name: "startkey", value: "\"LOGBOOK:\""),
                    URLQueryItem(name: "endkey", value: "\"LOGBOOK:\u{ffff}\""),
                ])

        var request = URLRequest(url: urlWithoutCredentials(url))
        request.httpMethod = "GET"
        if let authHeader = basicAuthHeader(from: couchURL) {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HAMRSError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            throw HAMRSError.invalidResponse("CouchDB error: HTTP \(httpResponse.statusCode)")
        }

        do {
            let result = try JSONDecoder().decode(
                CouchDBAllDocsResponse<HAMRSLogbook>.self,
                from: data
            )
            return result.rows.compactMap(\.doc)
        } catch {
            throw HAMRSError.decodingError(error)
        }
    }

    /// Fetch all QSOs from CouchDB
    private func fetchQSOs(from couchURL: URL) async throws -> [HAMRSQSO] {
        let url =
            couchURL
                .appendingPathComponent("_all_docs")
                .appending(queryItems: [
                    URLQueryItem(name: "include_docs", value: "true"),
                    URLQueryItem(name: "startkey", value: "\"QSO:\""),
                    URLQueryItem(name: "endkey", value: "\"QSO:\u{ffff}\""),
                ])

        var request = URLRequest(url: urlWithoutCredentials(url))
        request.httpMethod = "GET"
        if let authHeader = basicAuthHeader(from: couchURL) {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HAMRSError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            throw HAMRSError.invalidResponse("CouchDB error: HTTP \(httpResponse.statusCode)")
        }

        do {
            let result = try JSONDecoder().decode(
                CouchDBAllDocsResponse<HAMRSQSO>.self,
                from: data
            )
            return result.rows.compactMap(\.doc)
        } catch {
            throw HAMRSError.decodingError(error)
        }
    }
}
