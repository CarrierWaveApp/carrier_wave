import Foundation

// MARK: - Park Stats

extension ActivitiesClient {
    /// Fetch POTA statistics for a specific park (top activators, hunters, QSO counts).
    func fetchParkStats(reference: String) async throws -> ParkStatsResponse {
        let encoded = reference.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? reference
        let url = try buildURL(baseURL, path: "/v1/pota/stats/park/\(encoded)")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<ParkStatsResponse>.self,
            from: data
        )
        return apiResponse.data
    }
}

// MARK: - ParkStatsResponse

struct ParkStatsResponse: Codable {
    let reference: String
    let name: String
    let locationDesc: String?
    let state: String?
    let latitude: Double?
    let longitude: Double?
    let grid: String?
    let active: Bool
    let totalAttempts: Int
    let totalActivations: Int
    let totalQsos: Int
    let topActivators: [RankedCallsign]
    let topHunters: [RankedCallsign]
}

// MARK: - RankedCallsign

struct RankedCallsign: Codable, Identifiable {
    let callsign: String
    let count: Int

    var id: String {
        callsign
    }
}
