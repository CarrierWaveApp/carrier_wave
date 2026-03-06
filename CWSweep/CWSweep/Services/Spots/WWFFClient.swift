import Foundation

// MARK: - WWFFError

enum WWFFError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from WWFF Spotline"
        case let .httpError(code):
            "WWFF Spotline returned HTTP \(code)"
        }
    }
}

// MARK: - WWFFClient

/// Client for the WWFF Spotline API (spots.wwff.co).
/// Fetches active spots for WWFF activators.
actor WWFFClient {
    // MARK: Internal

    /// Fetch all recent WWFF spots.
    func fetchSpots() async throws -> [WWFFSpot] {
        guard let url = URL(string: "\(baseURL)/spots.json") else {
            throw WWFFError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw WWFFError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw WWFFError.httpError(http.statusCode)
        }

        return try JSONDecoder().decode([WWFFSpot].self, from: data)
    }

    /// Fetch spots for a specific activator callsign (client-side filter).
    func fetchSpots(for callsign: String) async throws -> [WWFFSpot] {
        let allSpots = try await fetchSpots()
        let upper = callsign.uppercased()
        return allSpots.filter { $0.activator.uppercased() == upper }
    }

    // MARK: Private

    private let baseURL = "https://spots.wwff.co"
}
