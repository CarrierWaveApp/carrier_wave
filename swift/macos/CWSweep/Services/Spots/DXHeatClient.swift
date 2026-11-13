import Foundation

// MARK: - DXHeatError

enum DXHeatError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid DXHeat API URL"
        case let .networkError(error):
            "DXHeat network error: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid DXHeat response: \(message)"
        }
    }
}

// MARK: - DXHeatClient

/// Client for the DXHeat REST API (dxheat.com)
actor DXHeatClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    /// Fetch recent spots from DXHeat
    func fetchSpots(limit: Int = 50) async throws -> [DXHeatSpot] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        guard let url = components.url else {
            throw DXHeatError.invalidURL
        }

        let (data, response) = try await performRequest(url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DXHeatError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            throw DXHeatError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode([DXHeatSpot].self, from: data)
    }

    // MARK: Private

    private let baseURL = "https://dxheat.com/source/spots/"
    private let session: URLSession

    private func performRequest(_ url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            throw DXHeatError.networkError(error)
        }
    }
}
