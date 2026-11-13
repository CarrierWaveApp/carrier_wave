import Foundation

// MARK: - DXWatchError

enum DXWatchError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid DXWatch API URL"
        case let .networkError(error):
            "DXWatch network error: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid DXWatch response: \(message)"
        }
    }
}

// MARK: - DXWatchClient

/// Client for the DXWatch compact JSON API (dxwatch.com)
actor DXWatchClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    /// Fetch recent spots from DXWatch.
    /// Uses incremental polling: first call fetches initial batch,
    /// subsequent calls fetch only spots newer than last seen ID.
    func fetchSpots(rows: Int = 50) async throws -> DXWatchResponse {
        var components = URLComponents(string: baseURL)!
        var queryItems = [
            URLQueryItem(name: "s", value: String(lastSpotId)),
            URLQueryItem(name: "r", value: String(rows)),
        ]
        // Initial load requires d=1
        if lastSpotId == 0 {
            queryItems.append(URLQueryItem(name: "d", value: "1"))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw DXWatchError.invalidURL
        }

        let (data, response) = try await performRequest(url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DXWatchError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            throw DXWatchError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }

        let dxResponse = try DXWatchResponseDecoder.decode(from: data)

        // Track highest spot ID for incremental polling
        if let maxId = dxResponse.spots.compactMap({ Int($0.id) }).max() {
            lastSpotId = maxId
        }

        return dxResponse
    }

    // MARK: Private

    private let baseURL = "https://dxwatch.com/dxsd1/s.php"
    private let session: URLSession
    private var lastSpotId: Int = 0

    private func performRequest(_ url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            throw DXWatchError.networkError(error)
        }
    }
}
