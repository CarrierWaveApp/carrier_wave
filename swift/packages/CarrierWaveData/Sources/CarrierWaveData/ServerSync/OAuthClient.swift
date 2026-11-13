import CarrierWaveCore
import Foundation

// MARK: - OAuthError

public enum OAuthError: Error {
    case notAuthenticated
    /// Polling exceeded its deadline without the magic link being clicked.
    case timedOut
}

// MARK: - OAuthClient

/// Phase 5 OAuth for the activities server. A thin Swift facade over the shared
/// Rust `AuthApi` (cw-net `AuthClient`): the PKCE magic-link → access + rotating
/// refresh → single-flight refresh protocol lives entirely in Rust, identical to
/// the Android client. Secret storage is delegated to the Keychain through
/// `KeychainSecureStore`; the short-lived access token is held in memory by the
/// Rust layer and never persisted.
///
/// Shared by Carrier Wave (iOS) and CW Sweep (macOS); the `platform` tag is what
/// the server records against the session.
public actor OAuthClient {
    // MARK: Lifecycle

    public init(baseURL: String? = nil, platform: String = OAuthClient.defaultPlatform, deviceName: String? = nil) {
        self.baseURL = ActivitiesServer.normalizeBase(baseURL ?? ActivitiesServer.resolvedBaseURL)
        self.platform = platform
        self.deviceName = deviceName
    }

    // MARK: Public

    public static var defaultPlatform: String {
        #if os(macOS)
            "macos"
        #else
            "ios"
        #endif
    }

    /// Whether a refresh token is stored (the device has an OAuth session).
    public func hasSession() -> Bool {
        (try? resolvedAPI())?.hasSession() ?? false
    }

    /// The account id from the last successful exchange, if any.
    public func accountID() -> String? {
        (try? resolvedAPI())?.accountId()
    }

    /// Whether a magic-link verification is in flight (started, not completed).
    public func hasPendingVerification() -> Bool {
        (try? resolvedAPI())?.hasPendingVerification() ?? false
    }

    /// The callsign of the in-flight verification, for UI display.
    public func pendingCallsign() -> String? {
        (try? resolvedAPI())?.pendingCallsign()
    }

    /// Abandon the in-flight verification (user cancelled).
    public func cancelPendingVerification() {
        try? resolvedAPI().cancelPendingVerification()
    }

    /// Step 1: request a magic link for `callsign`, persisting the PKCE verifier
    /// so completion survives relaunch. `email` is a fallback used only when the
    /// directory has no on-file address.
    public func startVerification(callsign: String, email: String?) async throws {
        try await resolvedAPI().startVerification(callsign: callsign, email: email)
    }

    /// Poll until the magic link is clicked, then persist the issued tokens.
    /// Throws ``OAuthError/timedOut`` if the link isn't clicked before `timeout`.
    public func pollForCompletion(timeout: TimeInterval = 180, interval: TimeInterval = 3) async throws {
        let outcome = try await resolvedAPI().pollForCompletion(
            timeoutSecs: UInt32(timeout),
            intervalSecs: UInt32(max(1, interval))
        )
        switch outcome {
        case .timedOut:
            throw OAuthError.timedOut
        case .signedIn,
             .attachedToAccount:
            break
        }
    }

    /// Universal-link return path: redeem a clicked verification `code` with the
    /// persisted PKCE verifier. Safe no-op if there's no pending verification.
    public func completeWithCode(_ code: String) async throws {
        try await resolvedAPI().completeWithCode(code: code)
    }

    /// Deep-link return path (App Link / custom scheme): mark the tapped magic
    /// link clicked, then finish sign-in on this device via the shared poll —
    /// or acknowledge if the sign-in was started on another device.
    public func completeFromLink(_ code: String) async throws -> FfiLinkOutcome {
        try await resolvedAPI().completeFromLink(code: code)
    }

    /// A currently-valid access token, refreshing if expired/absent. Throws when
    /// there is no OAuth session.
    public func validAccessToken() async throws -> String {
        try await resolvedAPI().validAccessToken()
    }

    /// Revoke this device's session (best-effort) and clear local state.
    public func logout() async {
        try? await resolvedAPI().logout()
    }

    // MARK: Private

    private let baseURL: String
    private let platform: String
    private let deviceName: String?
    private var api: AuthApi?

    /// Lazily build the Rust `AuthApi` over the Keychain-backed secure store.
    private func resolvedAPI() throws -> AuthApi {
        if let api {
            return api
        }
        let created = try AuthApi(
            secure: KeychainSecureStore(),
            baseUrl: baseURL,
            platform: platform,
            deviceName: deviceName
        )
        api = created
        return created
    }
}
