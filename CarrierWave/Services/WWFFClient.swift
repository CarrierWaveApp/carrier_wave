import CarrierWaveData
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
/// Fetches active spots and scheduled agendas for WWFF activators.
/// Includes DX cluster spots relayed through the Spotline service.
actor WWFFClient {
    // MARK: Internal

    /// Fetch all recent WWFF spots (includes DX cluster and RBN autospots).
    func fetchSpots() async throws -> [WWFFSpot] {
        try await fetchJSON("\(baseURL)/spots.json")
    }

    /// Fetch spots for a specific activator callsign (client-side filter).
    func fetchSpots(for callsign: String) async throws -> [WWFFSpot] {
        let allSpots = try await fetchSpots()
        let upper = callsign.uppercased()
        return allSpots.filter { $0.activator.uppercased() == upper }
    }

    /// Fetch the WWFF agenda (scheduled upcoming activations).
    func fetchAgenda() async throws -> [WWFFAgendaItem] {
        try await fetchJSON("\(baseURL)/agenda.json")
    }

    /// Fetch agenda items for a specific activator callsign (client-side filter).
    func fetchAgenda(for callsign: String) async throws -> [WWFFAgendaItem] {
        let allItems = try await fetchAgenda()
        let upper = callsign.uppercased()
        return allItems.filter { $0.activator.uppercased() == upper }
    }

    // MARK: Private

    private let baseURL = "https://spots.wwff.co"

    private func fetchJSON<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else {
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

        return try JSONDecoder().decode(T.self, from: data)
    }
}
