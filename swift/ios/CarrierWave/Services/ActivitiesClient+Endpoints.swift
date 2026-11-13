import CarrierWaveData
import Foundation

// MARK: - Additional Endpoints

extension ActivitiesClient {
    /// Check server health
    func healthCheck(sourceURL: String) async throws -> Bool {
        let url = try buildURL(sourceURL, path: "/v1/health")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        struct HealthResponse: Codable {
            var status: String
            var version: String
        }

        let healthResponse = try JSONDecoder.activitiesDecoder.decode(
            HealthResponse.self,
            from: data
        )
        return healthResponse.status == "ok"
    }
}
