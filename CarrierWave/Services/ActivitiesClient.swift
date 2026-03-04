import Foundation
import os

#if canImport(UIKit)
    import CarrierWaveData
    import UIKit
#endif

// MARK: - ActivitiesClient

@MainActor
final class ActivitiesClient {
    // MARK: Lifecycle

    init(baseURL: String = "https://activities.carrierwave.app") {
        self.baseURL = baseURL
    }

    // MARK: Internal

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "ActivitiesClient"
    )

    let keychain = KeychainHelper.shared

    let baseURL: String

    // MARK: - Authentication

    func saveAuthToken(_ token: String) throws {
        try keychain.save(token, for: KeychainHelper.Keys.activitiesAuthToken)
    }

    func getAuthToken() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.activitiesAuthToken)
    }

    func hasAuthToken() -> Bool {
        do {
            _ = try keychain.readString(for: KeychainHelper.Keys.activitiesAuthToken)
            return true
        } catch {
            return false
        }
    }

    func clearAuthToken() {
        try? keychain.delete(for: KeychainHelper.Keys.activitiesAuthToken)
    }

    func logout() {
        clearAuthToken()
    }

    /// Get a valid auth token, auto-registering if community features are enabled but
    /// no token exists (e.g., after reinstall or new device). Returns nil if community
    /// features are disabled or callsign is not set.
    func ensureAuthToken() async -> String? {
        if let token = try? getAuthToken() {
            return token
        }

        // No token — try auto-registering if community features are enabled
        let enabled = UserDefaults.standard.bool(forKey: "activitiesServerEnabled")
        let callsign = UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        guard enabled, !callsign.isEmpty else {
            return nil
        }

        do {
            let response = try await register(
                callsign: callsign.uppercased(),
                deviceName: Self.deviceName,
                sourceURL: baseURL
            )
            Self.logger.info("Auto-registered to recover auth token")
            return response.deviceToken
        } catch {
            Self.logger.error("Auto-registration failed: \(error)")
            return nil
        }
    }

    // MARK: - Registration

    /// Register with the activities server so the user appears in friend search.
    /// Creates both a user record (for search) and a participant record (for auth token).
    func register(
        callsign: String,
        deviceName: String?,
        sourceURL: String
    ) async throws -> RegisterResponseDTO {
        let url = try buildURL(sourceURL, path: "/v1/register")
        var request = try buildRequest(url: url, method: "POST")

        let body = RegisterRequestBody(callsign: callsign, deviceName: deviceName)
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<RegisterResponseDTO>.self,
            from: data
        )

        // Store the device token for authenticated requests
        try saveAuthToken(apiResponse.data.deviceToken)

        return apiResponse.data
    }

    // MARK: - Account Deletion

    /// Delete the authenticated user's account and all server-side data.
    /// Clears the local auth token on success.
    func deleteAccount() async throws {
        let authToken = try getAuthToken()
        let url = try buildURL(baseURL, path: "/v1/account")
        let request = try buildRequest(url: url, method: "DELETE", authToken: authToken)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ActivitiesError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 204 else {
            try validateResponse(response, data: data)
            return
        }

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
            throw ActivitiesError.invalidServerURL
        }

        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
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

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
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

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
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
        request.httpBody = try JSONEncoder.activitiesEncoder.encode(report)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
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

        let apiResponse = try JSONDecoder.activitiesDecoder.decode(
            APIResponse<ServerProgress>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Request Building

    func buildURL(_ base: String, path: String) throws -> URL {
        guard let url = URL(string: base + path) else {
            throw ActivitiesError.invalidServerURL
        }
        return url
    }

    func buildRequest(
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

    func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw ActivitiesError.networkError(error)
        }
    }

    func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ActivitiesError.invalidResponse("Not an HTTP response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            // Try to parse API error response
            if let errorResponse = try? JSONDecoder.activitiesDecoder.decode(
                APIErrorResponse.self,
                from: data
            ) {
                throw ActivitiesError.from(
                    apiCode: errorResponse.error.code,
                    message: errorResponse.error.message
                )
            }

            let message = String(data: data, encoding: .utf8)
            throw ActivitiesError.serverError(httpResponse.statusCode, message)
        }
    }

    // MARK: Private

    private static let deviceName: String = {
        #if canImport(UIKit)
            UIDevice.current.name
        #else
            "Unknown Device"
        #endif
    }()

    private let userAgent = "CarrierWave/1.0"
}

// MARK: - JSON Encoder Extension

extension JSONEncoder {
    static let activitiesEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
    static let activitiesDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
