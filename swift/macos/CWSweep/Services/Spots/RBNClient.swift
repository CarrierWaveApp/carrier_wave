import CarrierWaveCore
import Foundation

// MARK: - RBNError

enum RBNError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse(String)
    case rateLimited
    case noData

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid RBN API URL"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid response: \(message)"
        case .rateLimited:
            "RBN API rate limit exceeded"
        case .noData:
            "No data received from RBN"
        }
    }
}

// MARK: - RBNClient

/// Client for the Vail ReRBN API
actor RBNClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    /// Fetch spots for a specific callsign
    func spots(for callsign: String, hours: Int = 6, limit: Int = 50) async throws -> [RBNSpot] {
        var components = URLComponents(string: "\(baseURL)/spots")!
        let since = Date().addingTimeInterval(-Double(hours) * 3_600)
        let formatter = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "call", value: callsign.uppercased()),
            URLQueryItem(name: "since", value: formatter.string(from: since)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components.url else {
            throw RBNError.invalidURL
        }
        return try await fetchSpots(from: url)
    }

    /// Fetch spots filtered by band and/or mode
    func spots(
        band: String? = nil,
        mode: String? = nil,
        since: Date? = nil,
        limit: Int = 100
    ) async throws -> [RBNSpot] {
        var components = URLComponents(string: "\(baseURL)/spots")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        if let band {
            queryItems.append(URLQueryItem(name: "band", value: band))
        }
        if let mode {
            queryItems.append(URLQueryItem(name: "mode", value: mode))
        }
        if let since {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "since", value: formatter.string(from: since)))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw RBNError.invalidURL
        }
        return try await fetchSpots(from: url)
    }

    // MARK: Private

    private let baseURL = "https://activities.carrierwave.app/v1/rbn"
    private let session: URLSession

    private var rateLimitRemaining: Int = 100
    private var rateLimitReset: Date?

    private func fetchSpots(from url: URL) async throws -> [RBNSpot] {
        let (data, response) = try await performRequest(url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RBNError.invalidResponse("Not an HTTP response")
        }

        checkRateLimitHeaders(httpResponse)

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                throw RBNError.rateLimited
            }
            throw RBNError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }

        // Decoding (callsign-echo / total-count / bare-array shapes) is shared
        // with Android via the Rust core (`cw_net::rbn`).
        guard let json = String(bytes: data, encoding: .utf8),
              let spots = RBNSpot.decodeResponse(json)
        else {
            throw RBNError.invalidResponse("Unable to decode RBN spots")
        }
        return spots
    }

    private func performRequest(_ url: URL) async throws -> (Data, URLResponse) {
        if rateLimitRemaining <= 0, let reset = rateLimitReset, Date() < reset {
            throw RBNError.rateLimited
        }
        do {
            return try await session.data(from: url)
        } catch {
            throw RBNError.networkError(error)
        }
    }

    private func checkRateLimitHeaders(_ response: HTTPURLResponse) {
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           let remainingInt = Int(remaining)
        {
            rateLimitRemaining = remainingInt
        }
        if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetTimestamp = Double(reset)
        {
            rateLimitReset = Date(timeIntervalSince1970: resetTimestamp)
        }
    }
}
