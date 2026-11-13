// Tiles on the Air (TOTA) API client.
//
// Backed by Supabase Edge Functions at icneuzxitdqtofutxbla.supabase.co.
// Auth is a static API key generated from the user's tilesontheair.com profile,
// passed via `x-api-key`. Reads (spots) work without a key but rate-limit harder.
//
// Extensions split by concern:
//   - TOTAClient+Spots:       GET  /functions/v1/spots
//   - TOTAClient+Activations: POST /functions/v1/activations  (JSON, self-spot + log)
//   - TOTAClient+Upload:      POST /functions/v1/activations  (multipart, ADIF upload)

import CarrierWaveData
import UIKit

@MainActor
final class TOTAClient {
    // MARK: Lifecycle

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Internal

    static let shared = TOTAClient()

    /// Base URL for the public TOTA API. Matches the value baked into the
    /// tilesontheair.com web app — there is no separate dev environment.
    let baseURL = "https://icneuzxitdqtofutxbla.supabase.co/functions/v1"

    let session: URLSession
    let keychain = KeychainHelper.shared

    // MARK: - Configuration

    var isConfigured: Bool {
        getApiKey()?.isEmpty == false
    }

    // MARK: - Shared coding helpers

    /// Decoder that handles ISO 8601 timestamps with optional fractional seconds,
    /// matching what the TOTA edge functions emit (`2026-05-01T18:42:11Z`, occasionally
    /// `…11.123Z`). Built per-call because `JSONDecoder`/`ISO8601DateFormatter` aren't
    /// `Sendable` in Swift 6 — JSON volume is small enough that a fresh instance per
    /// request is cheaper than the workaround.
    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: raw) {
                return date
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised TOTA date: \(raw)"
            )
        }
        return decoder
    }

    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func getApiKey() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.totaApiKey)
    }

    /// Persist a new API key. No server-side validation endpoint is documented;
    /// callers should follow up with a real request to verify the key works.
    func setApiKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TOTAError.notAuthenticated
        }
        try keychain.save(trimmed, for: KeychainHelper.Keys.totaApiKey)
    }

    func clearApiKey() {
        try? keychain.delete(for: KeychainHelper.Keys.totaApiKey)
    }

    // MARK: - Request helpers

    /// Builds a URL request against the TOTA edge functions, attaching the API
    /// key when one is configured. Pass `requireAuth: true` for endpoints that
    /// reject anonymous traffic (currently only POST /activations).
    func makeRequest(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        requireAuth: Bool = false
    ) throws -> URLRequest {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw TOTAError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw TOTAError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let key = getApiKey(), !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        } else if requireAuth {
            throw TOTAError.notAuthenticated
        }

        return request
    }

    /// Executes a request and validates the HTTP status, returning the raw body
    /// for the caller to decode. Centralises rate-limit and HTTP error handling.
    func executeRequest(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TOTAError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TOTAError.invalidResponse
        }

        switch http.statusCode {
        case 200 ..< 300:
            return data
        case 429:
            throw TOTAError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TOTAError.httpError(status: http.statusCode, body: body)
        }
    }

    // MARK: Private
}
