import CarrierWaveCwFfi
import Foundation

// MARK: - PSKReporterError

public enum PSKReporterError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case parseError(String)
    case rateLimited

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from PSK Reporter"
        case let .httpError(code):
            "PSK Reporter returned HTTP \(code)"
        case let .parseError(message):
            "Failed to parse PSK Reporter response: \(message)"
        case .rateLimited:
            "PSK Reporter rate limit exceeded (5-minute minimum interval)"
        }
    }
}

// MARK: - PSKReporterClient

/// Client for the PSK Reporter HTTP query API.
/// Returns reception reports for digital mode activity (FT8, FT4, CW, etc.).
///
/// API docs: https://pskreporter.info/pskdev.html
/// Rate limit: maximum one request per 5 minutes.
public actor PSKReporterClient {
    // MARK: Lifecycle

    public init(appContact: String = "carrierwave-app@example.com") {
        self.appContact = appContact

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: Public

    /// Fetch reception reports for a specific sender (who heard me?).
    /// - Parameters:
    ///   - callsign: The transmitting station's callsign.
    ///   - seconds: How far back to look (negative, max -86400). Default: -1800 (30 min).
    /// - Returns: Array of reception reports.
    public func fetchSenderSpots(
        callsign: String,
        seconds: Int = -1_800
    ) async throws -> [PSKReporterSpot] {
        var components = baseComponents()
        components.queryItems?.append(contentsOf: [
            URLQueryItem(name: "senderCallsign", value: callsign.uppercased()),
            URLQueryItem(name: "flowStartSeconds", value: String(seconds)),
        ])
        return try await fetch(components: components)
    }

    /// Fetch reception reports filtered by mode and frequency range.
    /// Useful for hunter mode — shows all digital activity on a band.
    /// - Parameters:
    ///   - mode: Mode filter (e.g., "FT8", "FT4").
    ///   - minFreqHz: Minimum frequency in Hz (e.g., 14_000_000 for 20m).
    ///   - maxFreqHz: Maximum frequency in Hz (e.g., 14_100_000).
    ///   - seconds: How far back to look (default: -1800 = 30 min).
    ///   - limit: Maximum reports to return (default: 100).
    /// - Returns: Array of reception reports.
    public func fetchSpots(
        mode: String,
        minFreqHz: Int,
        maxFreqHz: Int,
        seconds: Int = -1_800,
        limit: Int = 100
    ) async throws -> [PSKReporterSpot] {
        var components = baseComponents()
        components.queryItems?.append(contentsOf: [
            URLQueryItem(name: "mode", value: mode),
            URLQueryItem(name: "frange", value: "\(minFreqHz)-\(maxFreqHz)"),
            URLQueryItem(name: "flowStartSeconds", value: String(seconds)),
            URLQueryItem(name: "rptlimit", value: String(limit)),
        ])
        return try await fetch(components: components)
    }

    // MARK: Private

    private let baseURL = "https://retrieve.pskreporter.info/query"
    private let appContact: String
    private let session: URLSession

    /// Minimum interval between requests (PSK Reporter policy: 5 minutes)
    private let minRequestInterval: TimeInterval = 300

    /// Track last request time to enforce rate limit
    private var lastRequestTime: Date?

    private func baseComponents() -> URLComponents {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "rronly", value: "1"),
            URLQueryItem(name: "noactive", value: "1"),
            URLQueryItem(name: "appcontact", value: appContact),
        ]
        return components
    }

    private func fetch(components: URLComponents) async throws -> [PSKReporterSpot] {
        // Enforce 5-minute rate limit
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minRequestInterval {
                throw PSKReporterError.rateLimited
            }
        }

        guard let url = components.url else {
            throw PSKReporterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")

        let (data, response) = try await session.data(for: request)
        lastRequestTime = Date()

        guard let http = response as? HTTPURLResponse else {
            throw PSKReporterError.invalidResponse
        }

        if http.statusCode == 429 {
            throw PSKReporterError.rateLimited
        }

        guard http.statusCode == 200 else {
            throw PSKReporterError.httpError(http.statusCode)
        }

        guard let xml = String(data: data, encoding: .utf8) else {
            throw PSKReporterError.parseError("Could not decode XML response")
        }
        guard let spots = PSKReporterSpot.decodeResponse(xml) else {
            throw PSKReporterError.parseError("XML parse failed")
        }
        return spots
    }
}
