import CarrierWaveCore
import CarrierWaveData
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

// MARK: - RBNStats

/// Aggregate statistics from RBN
struct RBNStats {
    let totalSpots: Int
    let activityRate: Double
    let topBands: [String: Int]
    let topModes: [String: Int]
}

// MARK: Decodable

extension RBNStats: Decodable {
    private enum CodingKeys: String, CodingKey {
        case totalSpots = "total_spots"
        case activityRate = "activity_rate"
        case topBands = "bands"
        case topModes = "modes"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSpots = try container.decode(Int.self, forKey: .totalSpots)
        activityRate = try container.decode(Double.self, forKey: .activityRate)
        topBands = try container.decode([String: Int].self, forKey: .topBands)
        topModes = try container.decode([String: Int].self, forKey: .topModes)
    }
}

// MARK: - RBNSkimmer

/// An active skimmer from the RBN network
struct RBNSkimmer: Identifiable {
    let spotter: String
    let spotCount: Int
    let lastSpot: Date?
    let modes: [String]?

    var id: String {
        spotter
    }

    /// Alias for compatibility
    var callsign: String {
        spotter
    }
}

// MARK: Decodable

extension RBNSkimmer: Decodable {
    enum CodingKeys: String, CodingKey {
        case spotter
        case spotCount
        case lastSpot
        case modes
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spotter = try container.decode(String.self, forKey: .spotter)
        spotCount = try container.decode(Int.self, forKey: .spotCount)
        lastSpot = try container.decodeIfPresent(Date.self, forKey: .lastSpot)
        modes = try container.decodeIfPresent([String].self, forKey: .modes)
    }
}

// MARK: - RBNSkimmersResponse

/// Response wrapper from the /skimmers endpoint
struct RBNSkimmersResponse {
    let count: Int
    let hours: Int
    let skimmers: [RBNSkimmer]
}

// MARK: Decodable

extension RBNSkimmersResponse: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decode(Int.self, forKey: .count)
        hours = try container.decode(Int.self, forKey: .hours)
        skimmers = try container.decode([RBNSkimmer].self, forKey: .skimmers)
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case hours
        case skimmers
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

    /// Fetch spots for multiple callsign variants, merging and deduplicating results.
    func spots(
        forVariants callsigns: [String],
        hours: Int = 1,
        limit: Int = 20
    ) async throws -> [RBNSpot] {
        var allSpots: [RBNSpot] = []
        var seenIDs: Set<Int> = []

        for callsign in callsigns {
            let fetched = await (try? spots(for: callsign, hours: hours, limit: limit)) ?? []
            for spot in fetched where !seenIDs.contains(spot.id) {
                seenIDs.insert(spot.id)
                allSpots.append(spot)
            }
        }

        return allSpots.sorted { $0.timestamp > $1.timestamp }
    }

    /// Fetch spots near a frequency (within bandwidthKHz)
    func spotsNearFrequency(
        _ frequencyMHz: Double,
        bandwidthKHz: Double = 2.0,
        mode: String? = nil,
        limit: Int = 50
    ) async throws -> [RBNSpot] {
        let freqKHz = frequencyMHz * 1_000
        let minFreq = freqKHz - bandwidthKHz
        let maxFreq = freqKHz + bandwidthKHz

        var urlString = "\(baseURL)/spots?minFreq=\(minFreq)&maxFreq=\(maxFreq)&limit=\(limit)"

        if let mode {
            urlString += "&mode=\(mode)"
        }

        guard let url = URL(string: urlString) else {
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

    /// Fetch aggregate statistics
    func stats(hours: Int = 1) async throws -> RBNStats {
        let urlString = "\(baseURL)/stats?hours=\(hours)"

        guard let url = URL(string: urlString) else {
            throw RBNError.invalidURL
        }

        let (data, response) = try await performRequest(url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RBNError.invalidResponse("Not an HTTP response")
        }

        checkRateLimitHeaders(httpResponse)

        guard httpResponse.statusCode == 200 else {
            throw RBNError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(RBNStats.self, from: data)
    }

    /// Fetch active skimmers from RBN
    /// - Parameter hours: Time range to consider (default 1 hour)
    /// - Returns: List of active skimmers with grid squares
    func fetchSkimmers(hours: Int = 1) async throws -> [RBNSkimmer] {
        var components = URLComponents(string: "\(baseURL)/skimmers")!
        components.queryItems = [
            URLQueryItem(name: "hours", value: String(hours)),
        ]

        guard let url = components.url else {
            throw RBNError.invalidURL
        }

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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let skimmersResponse = try decoder.decode(RBNSkimmersResponse.self, from: data)
        return skimmersResponse.skimmers
    }

    /// Fetch spots from a specific skimmer
    /// - Parameters:
    ///   - spotter: The skimmer callsign to filter by
    ///   - hours: Time range (default 1 hour)
    ///   - limit: Maximum spots to return (default 100)
    /// - Returns: List of spots from this skimmer
    func spots(spotter: String, hours: Int = 1, limit: Int = 100) async throws -> [RBNSpot] {
        var components = URLComponents(string: "\(baseURL)/spots")!
        components.queryItems = [
            URLQueryItem(name: "spotter", value: spotter),
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        // Add time filter
        let since = Date().addingTimeInterval(-Double(hours) * 3_600)
        let formatter = ISO8601DateFormatter()
        components.queryItems?.append(
            URLQueryItem(name: "since", value: formatter.string(from: since))
        )

        guard let url = components.url else {
            throw RBNError.invalidURL
        }

        return try await fetchSpots(from: url)
    }

    // MARK: Private

    private let baseURL = ActivitiesClient.normalizeBase(ActivitiesClient.resolvedBaseURL) + "/v1/rbn"
    private let session: URLSession

    // Cache for rate limiting
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
        // Check rate limit before making request
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
