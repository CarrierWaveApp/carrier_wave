import Foundation

// MARK: - DXSummitError

enum DXSummitError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid DX Summit API URL"
        case let .networkError(error):
            "DX Summit network error: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid DX Summit response: \(message)"
        }
    }
}

// MARK: - DXSummitClient

/// Client for the DX Summit REST API (dxsummit.fi)
actor DXSummitClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    /// Fetch recent spots from DX Summit
    func fetchSpots(limit: Int = 50) async throws -> [DXSummitSpot] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        guard let url = components.url else {
            throw DXSummitError.invalidURL
        }

        let (data, response) = try await performRequest(url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DXSummitError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            throw DXSummitError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        // DX Summit returns dates without timezone (e.g. "2026-03-24T01:49:15")
        // Standard .iso8601 requires the Z suffix, so try both formats
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            // Try ISO 8601 with timezone first
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: dateStr) {
                return date
            }
            // Fall back to no-timezone format (assume UTC)
            let bare = DateFormatter()
            bare.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            bare.timeZone = TimeZone(identifier: "UTC")
            bare.locale = Locale(identifier: "en_US_POSIX")
            if let date = bare.date(from: dateStr) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(dateStr)"
            )
        }
        return try decoder.decode([DXSummitSpot].self, from: data)
    }

    // MARK: Private

    private let baseURL = "http://www.dxsummit.fi/api/v1/spots"
    private let session: URLSession

    private func performRequest(_ url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            throw DXSummitError.networkError(error)
        }
    }
}
