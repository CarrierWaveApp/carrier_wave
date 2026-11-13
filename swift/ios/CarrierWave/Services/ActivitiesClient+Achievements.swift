import CarrierWaveData
import Foundation

// MARK: - ActivitiesClient Achievements Extension

extension ActivitiesClient {
    /// Fetch the public achievement catalog. Excludes secret achievements.
    func fetchAchievementCatalog(sourceURL: String) async throws -> [Achievement] {
        let url = try buildURL(sourceURL, path: "/v1/achievements")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let api = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<AchievementCatalogResponse>.self,
            from: data
        )
        return api.data.achievements
    }

    /// POST /v1/users/me/achievements/signal — report an ecosystem-usage signal.
    func reportAchievementSignal(
        id: String,
        authToken: String,
        sourceURL: String
    ) async throws {
        let url = try buildURL(sourceURL, path: "/v1/users/me/achievements/signal")
        var request = try buildRequest(url: url, method: "POST", authToken: authToken)
        let body: [String: String] = ["id": id]
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
    }

    /// Fetch the achievements awarded to a specific callsign.
    func fetchUserAchievements(
        callsign: String,
        sourceURL: String
    ) async throws -> [UserAchievement] {
        let normalized = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !normalized.isEmpty else {
            return []
        }

        let url = try buildURL(sourceURL, path: "/v1/users/\(normalized)/achievements")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let api = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<UserAchievementsResponse>.self,
            from: data
        )
        return api.data.awards
    }
}
