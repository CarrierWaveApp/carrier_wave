import CarrierWaveData
import Foundation

// MARK: - Programs API

extension ActivitiesClient {
    /// Fetch all available activity programs from the registry.
    /// No authentication required — programs are public configuration.
    func fetchPrograms() async throws -> ProgramListResponse {
        let url = try buildURL(baseURL, path: "/v1/programs")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<ProgramListResponse>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Fetch a single activity program by slug.
    func fetchProgram(slug: String) async throws -> ActivityProgram {
        let url = try buildURL(baseURL, path: "/v1/programs/\(slug)")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<ActivityProgram>.self,
            from: data
        )
        return apiResponse.data
    }
}
