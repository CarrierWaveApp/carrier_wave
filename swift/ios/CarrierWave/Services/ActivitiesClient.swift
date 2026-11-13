import Foundation
import OSLog

#if canImport(UIKit)
    import CarrierWaveData
    import UIKit
#endif

// MARK: - ActivitiesClient

@MainActor
final class ActivitiesClient {
    // MARK: Lifecycle

    init(baseURL: String? = nil) {
        self.baseURL = Self.normalizeBase(baseURL ?? Self.resolvedBaseURL)
    }

    // MARK: Internal

    nonisolated static let defaultURL = ActivitiesServer.defaultURL

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "ActivitiesClient"
    )

    /// Resolved base URL, respecting the developer override if set.
    /// `nonisolated` so non-MainActor contexts (PerfUploader, RBNClient) can access it.
    nonisolated static var resolvedBaseURL: String {
        ActivitiesServer.resolvedBaseURL
    }

    let keychain = KeychainHelper.shared

    /// Phase 5 OAuth session. When a session exists its access token is preferred
    /// over the legacy `fd_` device token (the server accepts both — dual-auth).
    let oauth = OAuthClient()

    let baseURL: String

    // MARK: - Request Building

    /// Strip trailing slashes from a base URL so concatenation with `/v1/...` never produces `//`.
    nonisolated static func normalizeBase(_ base: String) -> String {
        ActivitiesServer.normalizeBase(base)
    }

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

    /// Whether the device holds any server credential — an OAuth session or a
    /// legacy `fd_` device token. `hasAuthToken()` only sees the latter.
    func hasServerSession() async -> Bool {
        if await oauth.hasSession() {
            return true
        }
        return hasAuthToken()
    }

    /// Bearer token for account-scoped mutations (`/v1/account/*`). Prefers
    /// the OAuth access token so the server sees the caller's `account_id`:
    /// `change_callsign` only re-points the account's primary callsign for an
    /// account-authenticated caller, and `claim-previous` rejects legacy tokens
    /// outright. Sending the legacy `fd_` token here renamed the legacy tables
    /// but left the OAuth identity on the old call, so every later request
    /// acted as the old callsign (CAR-349). Unlike `ensureAuthToken()` this has
    /// no drift-sync or auto-register side effects, so the drift sync can call
    /// through it without recursing.
    func preferredAuthToken() async throws -> String {
        if await oauth.hasSession(), let access = try? await oauth.validAccessToken() {
            return access
        }
        return try getAuthToken()
    }

    func logout() {
        clearAuthToken()
    }

    /// Token for `/v1/sync/*` routes, which require an account-backed OAuth
    /// session (verified via a magic-link email) — the server rejects legacy
    /// `fd_` device tokens there with 403 ACCOUNT_REQUIRED, so unlike
    /// `ensureAuthToken()` this never falls back to one. Returns nil when the
    /// user hasn't verified their callsign + email yet.
    func syncAuthToken() async -> String? {
        guard await oauth.hasSession() else {
            return nil
        }
        return try? await oauth.validAccessToken()
    }

    /// Get a valid auth token, auto-registering if community features are enabled but
    /// no token exists (e.g., after reinstall or new device). Returns nil if community
    /// features are disabled or callsign is not set.
    ///
    /// Also detects callsign drift: if the local callsign differs from the last registered
    /// callsign, syncs the change to the server before returning the token.
    func ensureAuthToken() async -> String? {
        let currentCallsign = (
            UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        ).uppercased()

        // Phase 5: prefer an OAuth access token when a session exists. The server
        // accepts both schemes (dual-auth), so falling through to the legacy
        // `fd_` token below is safe if no session exists or a refresh fails.
        if await oauth.hasSession(), let access = try? await oauth.validAccessToken() {
            // Drift detection must run for OAuth sessions too: a callsign change
            // that never reached the server (offline, OAuth-only account) left
            // the account acting as the old call on every launch (CAR-349).
            // A successful change revokes outstanding access tokens server-side;
            // the Rust auth layer caches this one until it nears expiry (≤15
            // min), so calls in that window can 401 until the next refresh —
            // the same as any other server-side revocation today.
            await syncCallsignDriftIfNeeded(currentCallsign: currentCallsign)
            return access
        }

        if let token = try? getAuthToken() {
            // Check for callsign drift — sync if changed since last registration
            await syncCallsignDriftIfNeeded(currentCallsign: currentCallsign)
            return token
        }

        // No token — try auto-registering if community features are enabled
        let enabled = UserDefaults.standard.bool(forKey: "activitiesServerEnabled")
        guard enabled, !currentCallsign.isEmpty else {
            return nil
        }

        do {
            let response = try await register(
                callsign: currentCallsign,
                deviceName: Self.deviceName,
                sourceURL: baseURL
            )
            UserDefaults.standard.set(currentCallsign, forKey: Self.registeredCallsignKey)
            if let token = response.deviceToken {
                Self.logger.info("Auto-registered to recover auth token")
                return token
            }
            // The callsign is already registered, so the server withholds the
            // device token by design (CAR-304): unauthenticated re-register can no
            // longer recover another operator's token. Legacy by-callsign recovery
            // is gone — the user must sign in via magic-link to get an OAuth
            // session. Return nil so the caller can prompt sign-in.
            Self.logger.info("Callsign already registered; token recovery needs magic-link sign-in")
            return nil
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

        // Store the device token for authenticated requests. Absent for an
        // already-registered callsign (CAR-304) — nothing to save; token recovery
        // for that case goes through the magic-link sign-in flow.
        if let token = apiResponse.data.deviceToken {
            try saveAuthToken(token)
        }

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

    func buildURL(_ base: String, path: String) throws -> URL {
        guard let url = URL(string: Self.normalizeBase(base) + path) else {
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
