import Foundation

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - ChallengesClient

@MainActor
final class ChallengesClient {
    // MARK: Lifecycle

    init(baseURL: String = "https://activities.carrierwave.app") {
        self.baseURL = baseURL
    }

    // MARK: Internal

    let keychain = KeychainHelper.shared

    // MARK: - Authentication

    func saveAuthToken(_ token: String) throws {
        try keychain.save(token, for: KeychainHelper.Keys.challengesAuthToken)
    }

    func getAuthToken() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.challengesAuthToken)
    }

    func hasAuthToken() -> Bool {
        do {
            _ = try keychain.readString(for: KeychainHelper.Keys.challengesAuthToken)
            return true
        } catch {
            return false
        }
    }

    func clearAuthToken() {
        try? keychain.delete(for: KeychainHelper.Keys.challengesAuthToken)
    }

    func logout() {
        clearAuthToken()
    }

    // MARK: - Challenge Sources

    /// Fetch challenges with optional filters
    func fetchChallenges(
        from sourceURL: String,
        category: ChallengeCategory? = nil,
        type: ChallengeType? = nil,
        active: Bool? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> ChallengeListData {
        var components = URLComponents(string: sourceURL + "/v1/challenges")
        var queryItems: [URLQueryItem] = []

        if let category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        if let type {
            queryItems.append(URLQueryItem(name: "type", value: type.rawValue))
        }
        if let active {
            queryItems.append(URLQueryItem(name: "active", value: String(active)))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }

        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw ChallengesError.invalidServerURL
        }

        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.challengesDecoder.decode(
            APIResponse<ChallengeListData>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Fetch a single challenge definition
    func fetchChallenge(id: UUID, from sourceURL: String) async throws -> ChallengeDefinitionDTO {
        let url = try buildURL(sourceURL, path: "/v1/challenges/\(id.uuidString)")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.challengesDecoder.decode(
            APIResponse<ChallengeDefinitionDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Participation

    /// Join a challenge
    func joinChallenge(
        id: UUID,
        sourceURL: String,
        callsign: String,
        inviteToken: String? = nil
    ) async throws -> JoinChallengeData {
        let url = try buildURL(sourceURL, path: "/v1/challenges/\(id.uuidString)/join")
        var request = try buildRequest(url: url, method: "POST")

        let joinRequest = JoinChallengeRequest(
            callsign: callsign,
            deviceName: Self.deviceName,
            inviteToken: inviteToken
        )
        request.httpBody = try JSONEncoder().encode(joinRequest)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.challengesDecoder.decode(
            APIResponse<JoinChallengeData>.self,
            from: data
        )

        return apiResponse.data
    }

    /// Leave a challenge
    func leaveChallenge(id: UUID, sourceURL: String, authToken: String) async throws {
        let url = try buildURL(sourceURL, path: "/v1/challenges/\(id.uuidString)/leave")
        let request = try buildRequest(url: url, method: "DELETE", authToken: authToken)

        let (data, response) = try await performRequest(request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200,
                 204:
                return
            default:
                try validateResponse(response, data: data)
            }
        }
    }

    /// Report progress to server
    func reportProgress(
        challengeId: UUID,
        report: ProgressReportRequest,
        sourceURL: String,
        authToken: String
    ) async throws -> ProgressReportData {
        let url = try buildURL(sourceURL, path: "/v1/challenges/\(challengeId.uuidString)/progress")
        var request = try buildRequest(url: url, method: "POST", authToken: authToken)
        request.httpBody = try JSONEncoder.challengesEncoder.encode(report)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.challengesDecoder.decode(
            APIResponse<ProgressReportData>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Get current progress for authenticated user
    func getProgress(
        challengeId: UUID,
        sourceURL: String,
        authToken: String
    ) async throws -> ServerProgress {
        let url = try buildURL(sourceURL, path: "/v1/challenges/\(challengeId.uuidString)/progress")
        let request = try buildRequest(url: url, method: "GET", authToken: authToken)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.challengesDecoder.decode(
            APIResponse<ServerProgress>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Leaderboards

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
            throw ChallengesError.invalidServerURL
        }

        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.challengesDecoder.decode(
            APIResponse<LeaderboardData>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Participant Challenges

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

        let apiResponse = try JSONDecoder.challengesDecoder.decode(
            APIResponse<[ParticipatingChallengeDTO]>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Health Check

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

        let healthResponse = try JSONDecoder.challengesDecoder.decode(
            HealthResponse.self,
            from: data
        )
        return healthResponse.status == "ok"
    }

    // MARK: Private

    private static let deviceName: String = {
        #if canImport(UIKit)
            UIDevice.current.name
        #else
            "Unknown Device"
        #endif
    }()

    private let baseURL: String
    private let userAgent = "CarrierWave/1.0"

    // MARK: - Request Building

    private func buildURL(_ base: String, path: String) throws -> URL {
        guard let url = URL(string: base + path) else {
            throw ChallengesError.invalidServerURL
        }
        return url
    }

    private func buildRequest(
        url: URL,
        method: String,
        authToken: String? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw ChallengesError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChallengesError.invalidResponse("Not an HTTP response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            // Try to parse API error response
            if let errorResponse = try? JSONDecoder.challengesDecoder.decode(
                APIErrorResponse.self,
                from: data
            ) {
                throw ChallengesError.from(
                    apiCode: errorResponse.error.code,
                    message: errorResponse.error.message
                )
            }

            let message = String(data: data, encoding: .utf8)
            throw ChallengesError.serverError(httpResponse.statusCode, message)
        }
    }
}

// MARK: - JSON Encoder Extension

extension JSONEncoder {
    static let challengesEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
    static let challengesDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
