import CarrierWaveData
import Foundation

// MARK: - AccountService

/// CW Sweep's Carrier Wave account session: the magic-link sign-in flow over
/// the shared `OAuthClient` (Rust `AuthApi`, platform "macos") and the
/// signed-in state the settings UI and Carrier Wave Sync read. The link is
/// clicked in any browser; completion is detected by polling, so no URL
/// scheme is needed on the Mac.
@MainActor
@Observable
final class AccountService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    enum Phase: Equatable {
        case idle
        case sending
        case waiting
        case failed(String)
    }

    static let shared = AccountService()

    private(set) var isSignedIn = false
    private(set) var accountID: String?
    private(set) var phase: Phase = .idle

    /// The server the session state refers to.
    private(set) var server = ActivitiesServer.resolvedBaseURL

    /// Re-read the session state from the Rust auth layer. A stored session is
    /// only "signed in" if it still yields a token from the current server.
    func refresh() async {
        server = ActivitiesServer.resolvedBaseURL
        var signedIn = await oauth.hasSession()
        if signedIn, await (try? oauth.validAccessToken()) == nil {
            // Refresh token from another server (or revoked): treat as signed out.
            signedIn = false
        }
        isSignedIn = signedIn
        accountID = isSignedIn ? await oauth.accountID() : nil
        if await oauth.hasPendingVerification(), phase == .idle {
            // A link was requested in an earlier launch; resume waiting for it.
            phase = .waiting
            startPolling()
        }
    }

    /// Step 1: email a sign-in link for `callsign` (falling back to `email`
    /// when the directory has no address on file), then wait for the click.
    func requestLink(callsign: String, email: String?) {
        let call = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !call.isEmpty, phase != .sending else {
            return
        }
        let address = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .sending
        Task {
            do {
                try await Self.withTimeout(seconds: 30) {
                    try await self.oauth.startVerification(
                        callsign: call, email: address?.isEmpty == false ? address : nil
                    )
                }
                phase = .waiting
                startPolling()
            } catch is TimeoutError {
                phase = .failed("The sign-in server didn't respond within 30 seconds. "
                    + "Check the server URL in General settings and your connection.")
            } catch {
                phase = .failed("Couldn't send the sign-in link: \(error.localizedDescription)")
            }
        }
    }

    /// Abandon the in-flight link.
    func cancel() {
        pollTask?.cancel()
        pollTask = nil
        Task { await oauth.cancelPendingVerification() }
        phase = .idle
    }

    /// Revoke this Mac's session (best effort) and clear local state.
    func signOut() async {
        pollTask?.cancel()
        pollTask = nil
        await oauth.logout()
        isSignedIn = false
        accountID = nil
        phase = .idle
    }

    /// A valid bearer for account-scoped server calls, or nil when signed out.
    func accessToken() async -> String? {
        guard await oauth.hasSession() else {
            return nil
        }
        return try? await oauth.validAccessToken()
    }

    // MARK: Private

    private struct TimeoutError: Error {}

    private var pollTask: Task<Void, Never>?
    private var oauthCache: (base: String, client: OAuthClient)?

    /// OAuth client for the currently resolved server; rebuilt when the
    /// developer override moves the base URL. The session (refresh token)
    /// itself is one slot in the Keychain, so a session minted on one server
    /// is rejected by another — the user signs in again after switching.
    private var oauth: OAuthClient {
        let base = ActivitiesServer.resolvedBaseURL
        if let cached = oauthCache, cached.base == base {
            return cached.client
        }
        let fresh = OAuthClient(baseURL: base, deviceName: Host.current().localizedName)
        oauthCache = (base, fresh)
        return fresh
    }

    /// Run `operation`, throwing `TimeoutError` if it doesn't finish in `seconds`,
    /// so a hung FFI call can never leave the UI stuck on "Sending…".
    private static func withTimeout(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            do {
                try await oauth.pollForCompletion()
                guard !Task.isCancelled else {
                    return
                }
                isSignedIn = true
                accountID = await oauth.accountID()
                phase = .idle
            } catch is CancellationError {
                // Cancelled by the user; phase already reset.
            } catch OAuthError.timedOut {
                if !Task.isCancelled {
                    phase = .failed("The link wasn't clicked in time. Send a new one to try again.")
                }
            } catch {
                if !Task.isCancelled {
                    phase = .failed("Something went wrong finishing sign-in. Send a new link to try again.")
                }
            }
        }
    }
}
