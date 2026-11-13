import CarrierWaveCore
import Foundation
import Observation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

// MARK: - AMTService

/// Another Morse Trainer (AMT) account + stats for Field and CW Sweep. A thin
/// `@Observable` facade over the shared Rust `AmtApi`: the email-link PKCE
/// sign-in, single-flight token rotation, the `/v1/me/stats` fetch and the
/// offline snapshot all live in Rust (identical to Android); this layer
/// sequences the calls, keeps the UI-facing state, and throttles refreshes.
///
/// Secrets go to the Keychain via `KeychainSecureStore`. Everything AMT gives
/// us is read-only and the user can remove Carrier Wave from their AMT devices
/// at any time, after which the next refresh signs us out locally.
@MainActor
@Observable
public final class AMTService {
    // MARK: Lifecycle

    private init() {
        reloadFromStore()
        // AMT syncs happen in another app; re-check whenever we come back to
        // the foreground so a fresh practice session shows up without waiting
        // for the dashboard to be rebuilt.
        #if canImport(UIKit)
            let foreground = UIApplication.willEnterForegroundNotification
        #else
            let foreground = NSApplication.didBecomeActiveNotification
        #endif
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: foreground, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await AMTService.shared.refreshStatsIfNeeded()
            }
        }
    }

    // MARK: Public

    public static let shared = AMTService()

    /// Don't hit `/v1/me/stats` more often than this unless asked explicitly.
    /// The call is cheap and the AMT apps sync on their own schedule, so keep
    /// it short: every dashboard appearance / app foreground past this re-fetches.
    public static let refreshInterval: TimeInterval = 60

    /// Whether a refresh token is stored (the device is signed in to AMT).
    public private(set) var isSignedIn = false
    /// The signed-in account (id, callsign, display name), if any.
    public private(set) var account: FfiAmtAccount?
    /// The newest stats snapshot — cached from the last fetch, so present
    /// offline and across relaunch.
    public private(set) var stats: FfiAmtStats?
    /// Practice days keyed for the activity grid; recomputed when `stats` changes.
    public private(set) var activityByUTCDay: [Date: AMTDayActivity] = [:]
    /// The email of an in-flight sign-in (link sent, not yet confirmed).
    public private(set) var pendingEmail: String?
    public private(set) var isRefreshing = false
    /// Last refresh failure, for the settings screen. Cleared on success.
    public private(set) var lastError: String?
    public private(set) var lastRefreshAttempt: Date?

    public var currentStreak: Int? {
        stats.map { Int($0.streak.current) }
    }

    public var longestStreak: Int? {
        stats.map { Int($0.streak.longest) }
    }

    /// Re-read session, account, pending state and the cached snapshot from
    /// the secure store (cheap Keychain reads).
    public func reloadFromStore() {
        guard let api = try? resolvedAPI() else {
            return
        }
        isSignedIn = api.hasSession()
        account = api.account()
        pendingEmail = api.pendingEmail()
        setStats(api.cachedStats())
    }

    /// Step 1: AMT emails `email` a sign-in link. Always succeeds server-side,
    /// whether or not the address has an AMT account.
    public func startSignIn(email: String) async throws {
        let api = try resolvedAPI()
        try await api.startSignIn(email: email)
        pendingEmail = api.pendingEmail()
        lastError = nil
    }

    /// Poll until the user presses Confirm in the email (or the deadline
    /// passes). On `signedIn` the first stats fetch is kicked off.
    public func pollForCompletion(timeoutSeconds: UInt32 = 300) async throws -> FfiAmtSignInOutcome {
        let api = try resolvedAPI()
        let outcome = try await api.pollForCompletion(timeoutSecs: timeoutSeconds)
        isSignedIn = api.hasSession()
        account = api.account()
        pendingEmail = api.pendingEmail()
        if outcome == .signedIn {
            await refreshStats()
        }
        return outcome
    }

    public func cancelPendingSignIn() {
        (try? resolvedAPI())?.cancelPendingSignIn()
        pendingEmail = nil
    }

    /// Refresh if signed in and the last attempt is older than `refreshInterval`.
    /// Safe to call from every dashboard appearance.
    public func refreshStatsIfNeeded() async {
        guard isSignedIn else {
            return
        }
        if let last = lastRefreshAttempt, Date().timeIntervalSince(last) < Self.refreshInterval {
            return
        }
        await refreshStats()
    }

    /// Fetch `/v1/me/stats` now (one refresh-and-retry on 401 happens in Rust).
    /// Returns whether the fetch succeeded; failures leave the cached snapshot
    /// in place and are reported through `lastError`. A dead session (the
    /// user removed Carrier Wave in AMT) flips `isSignedIn` to false.
    @discardableResult
    public func refreshStats() async -> Bool {
        guard !isRefreshing, let api = try? resolvedAPI() else {
            return false
        }
        isRefreshing = true
        lastRefreshAttempt = Date()
        defer { isRefreshing = false }
        do {
            let fresh = try await api.refreshStats(today: AMTActivityFormatting.localToday())
            setStats(fresh)
            account = api.account()
            lastError = nil
            return true
        } catch {
            lastError = Self.describe(error)
            // `CwError.Auth` after a failed refresh means AMT ended the session
            // and Rust already cleared the local one; mirror it.
            isSignedIn = api.hasSession()
            if !isSignedIn {
                account = nil
                setStats(nil)
            }
            return false
        }
    }

    /// Sign out of AMT (best-effort server call) and forget everything local.
    public func signOut() async {
        guard let api = try? resolvedAPI() else {
            return
        }
        try? await api.signOut()
        isSignedIn = false
        account = nil
        pendingEmail = nil
        lastError = nil
        setStats(nil)
    }

    // MARK: Private

    private static var platform: String {
        #if os(macOS)
            "macos"
        #else
            "ios"
        #endif
    }

    private static var deviceName: String? {
        #if os(macOS)
            Host.current().localizedName
        #elseif canImport(UIKit)
            UIDevice.current.name
        #else
            nil
        #endif
    }

    private var api: AmtApi?
    private var foregroundObserver: NSObjectProtocol?

    private static func describe(_ error: Error) -> String {
        if let cw = error as? CwError {
            switch cw {
            case let .Auth(reason),
                 let .Network(reason),
                 let .Query(reason),
                 let .Store(reason),
                 let .Crypto(reason):
                return reason
            }
        }
        return error.localizedDescription
    }

    private func resolvedAPI() throws -> AmtApi {
        if let api {
            return api
        }
        let created = try AmtApi(
            secure: KeychainSecureStore(),
            platform: Self.platform,
            deviceName: Self.deviceName
        )
        api = created
        return created
    }

    private func setStats(_ new: FfiAmtStats?) {
        stats = new
        activityByUTCDay = new.map(AMTActivityFormatting.activityByUTCDay) ?? [:]
    }
}
