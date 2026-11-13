import Foundation

// MARK: - SpotMarker

struct SpotMarker: Codable {
    let marker: String
    let callsign: String
    let createdAt: Date
}

// MARK: - Spot Markers

extension ActivitiesClient {
    /// Generate a new spot marker for SMS spotting.
    /// Replaces any existing marker for the authenticated callsign.
    func generateSpotMarker() async throws -> SpotMarker {
        let authToken = try getAuthToken()
        let url = try buildURL(baseURL, path: "/v1/spot-markers")
        let request = try buildRequest(url: url, method: "POST", authToken: authToken)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201
        else {
            try validateResponse(response, data: data)
            // validateResponse throws on non-2xx, so this is unreachable
            throw ActivitiesError.invalidResponse("Unexpected status for spot marker creation")
        }

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<SpotMarker>.self,
            from: data
        )
        return apiResponse.data
    }
}
