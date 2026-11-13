import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CarrierWaveData", category: "SmartLinkAuth")

// MARK: - SmartLinkAuth

/// Auth0-based authentication for FlexRadio SmartLink.
/// Uses the password grant flow to obtain JWT id_token and refresh_token.
public actor SmartLinkAuth {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Current tokens (nil if not authenticated)
    public private(set) var tokens: SmartLinkTokens?

    /// Whether we have a valid refresh token
    public var isAuthenticated: Bool {
        tokens?.refreshToken != nil
    }

    /// Login with SmartLink email and password.
    /// Returns tokens on success.
    public func login(email: String, password: String) async throws -> SmartLinkTokens {
        let body: [String: String] = [
            "client_id": Self.clientId,
            "connection": "Username-Password-Authentication",
            "device": "CarrierWave",
            "grant_type": "password",
            "username": email,
            "password": password,
            "scope": Self.scope,
        ]

        let result: AuthResponse = try await postJSON(
            url: Self.authenticateURL,
            body: body
        )

        let newTokens = SmartLinkTokens(
            idToken: result.idToken,
            refreshToken: result.refreshToken
        )
        tokens = newTokens
        logger.info("SmartLink login successful")
        return newTokens
    }

    /// Refresh the id_token using a stored refresh_token.
    /// JWT id_tokens expire after 60 seconds, so this must be called before connecting.
    public func refreshIdToken(refreshToken: String) async throws -> SmartLinkTokens {
        let body: [String: String] = [
            "client_id": Self.clientId,
            "grant_type": Self.grantTypeRefresh,
            "refresh_token": refreshToken,
            "target": Self.clientId,
            "scope": Self.scope,
        ]

        let result: DelegationResponse = try await postJSON(
            url: Self.delegationURL,
            body: body
        )

        let newTokens = SmartLinkTokens(
            idToken: result.idToken,
            refreshToken: refreshToken
        )
        tokens = newTokens
        logger.info("SmartLink token refresh successful")
        return newTokens
    }

    /// Clear tokens (logout)
    public func logout() {
        tokens = nil
        logger.info("SmartLink logged out")
    }

    // MARK: Private

    // Auth0 configuration (production — "frtest" is the production tenant)
    private static let clientId = "4Y9fEIIsVYyQo5u6jr7yBWc4lV5ugC2m"
    private static let scope = "openid offline_access email picture"
    private static let authenticateURL = "https://frtest.auth0.com/oauth/ro"
    private static let delegationURL = "https://frtest.auth0.com/delegation"
    private static let grantTypeRefresh = "urn:ietf:params:oauth:grant-type:jwt-bearer"

    private func postJSON<T: Decodable>(url urlString: String, body: [String: String]) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw SmartLinkAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SmartLinkAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            logger.error("Auth0 error \(httpResponse.statusCode): \(errorBody)")
            throw SmartLinkAuthError.authFailed(httpResponse.statusCode, errorBody)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - SmartLinkTokens

/// Auth0 token pair for SmartLink authentication.
public struct SmartLinkTokens: Sendable {
    // MARK: Lifecycle

    public init(idToken: String, refreshToken: String) {
        self.idToken = idToken
        self.refreshToken = refreshToken
    }

    // MARK: Public

    public let idToken: String
    public let refreshToken: String
}

// MARK: - SmartLinkAuthError

public enum SmartLinkAuthError: LocalizedError {
    case invalidURL
    case invalidResponse
    case authFailed(Int, String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid Auth0 URL"
        case .invalidResponse:
            "Invalid response from Auth0"
        case let .authFailed(code, message):
            "SmartLink login failed (\(code)): \(message)"
        }
    }
}

// MARK: - AuthResponse

private struct AuthResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case refreshToken = "refresh_token"
    }

    let idToken: String
    let refreshToken: String
}

// MARK: - DelegationResponse

private struct DelegationResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }

    let idToken: String
}
