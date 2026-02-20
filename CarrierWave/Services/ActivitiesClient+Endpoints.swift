import Foundation

// MARK: - Leaderboards & Participant Challenges

extension ActivitiesClient {
    /// Fetch leaderboard for a challenge
    func fetchLeaderboard(
        challengeId: UUID,
        sourceURL: String,
        limit: Int? = nil,
        offset: Int? = nil,
        around: String? = nil
    ) async throws -> LeaderboardData {
        var components = URLComponents(
            string: sourceURL + "/v1/challenges/\(challengeId.uuidString)/leaderboard"
        )
        var queryItems: [URLQueryItem] = []

        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        if let around {
            queryItems.append(URLQueryItem(name: "around", value: around))
        }

        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw ActivitiesError.invalidServerURL
        }

        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<LeaderboardData>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Fetch all challenges a callsign has joined
    func fetchParticipatingChallenges(
        callsign: String,
        sourceURL: String,
        authToken: String
    ) async throws -> [ParticipatingChallengeDTO] {
        let encodedCallsign =
            callsign.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? callsign
        let url = try buildURL(sourceURL, path: "/v1/participants/\(encodedCallsign)/challenges")
        let request = try buildRequest(url: url, method: "GET", authToken: authToken)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<[ParticipatingChallengeDTO]>.self,
            from: data
        )
        return apiResponse.data
    }

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
