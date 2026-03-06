import Foundation

// MARK: - POTASpotsError

enum POTASpotsError: Error, LocalizedError {
    case invalidURL
    case fetchFailed(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid POTA API URL"
        case let .fetchFailed(message):
            "POTA spots fetch failed: \(message)"
        }
    }
}

// MARK: - POTASpotsClient

/// Lightweight POTA client for fetching spots (unauthenticated endpoints only).
/// Does not require POTAAuthService — only hits public API endpoints.
actor POTASpotsClient {
    // MARK: Internal

    /// Fetch all currently active POTA spots (no auth required)
    func fetchActiveSpots() async throws -> [POTASpot] {
        guard let url = URL(string: "\(baseURL)/spot/activator") else {
            throw POTASpotsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTASpotsError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTASpotsError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode([POTASpot].self, from: data)
    }

    /// Fetch spots for a specific callsign from active spots
    func fetchSpots(for callsign: String) async throws -> [POTASpot] {
        let allSpots = try await fetchActiveSpots()
        let upper = callsign.uppercased()
        return allSpots.filter { $0.activator.uppercased() == upper }
    }

    // MARK: Private

    private let baseURL = "https://api.pota.app"
}
