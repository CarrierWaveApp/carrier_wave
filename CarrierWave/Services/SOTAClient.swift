import CarrierWaveData
import Foundation

// MARK: - SOTAError

enum SOTAError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from SOTA API"
        case let .httpError(code):
            "SOTA API returned HTTP \(code)"
        }
    }
}

// MARK: - SOTAClient

/// Client for the SOTAwatch API (api2.sota.org.uk).
/// Fetches active spots for SOTA activators.
actor SOTAClient {
    // MARK: Internal

    /// Fetch the most recent SOTA spots.
    /// - Parameters:
    ///   - count: Maximum number of spots to fetch (default 50, API max 200).
    ///   - association: Association filter, e.g. "W4C". Pass nil for all associations.
    /// - Returns: Array of SOTA spots, newest first.
    func fetchSpots(count: Int = 50, association: String? = nil) async throws -> [SOTASpot] {
        let filter = association ?? "all"
        guard let url = URL(string: "\(baseURL)/spots/\(count)/\(filter)") else {
            throw SOTAError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SOTAError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw SOTAError.httpError(http.statusCode)
        }

        return try JSONDecoder().decode([SOTASpot].self, from: data)
    }

    /// Fetch spots for a specific activator callsign (filters client-side).
    /// - Parameters:
    ///   - callsign: The activator's callsign.
    ///   - count: Number of recent spots to search through (default 50).
    /// - Returns: Spots matching the activator callsign.
    func fetchSpots(for callsign: String, count: Int = 50) async throws -> [SOTASpot] {
        let allSpots = try await fetchSpots(count: count)
        let upper = callsign.uppercased()
        return allSpots.filter { $0.activatorCallsign.uppercased() == upper }
    }

    // MARK: Private

    private let baseURL = "https://api2.sota.org.uk/api"
}
