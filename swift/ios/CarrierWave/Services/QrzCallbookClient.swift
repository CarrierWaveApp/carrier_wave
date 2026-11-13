import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - QrzCallbookError

enum QrzCallbookError: Error {
    /// No QRZ Callbook credentials are stored.
    case noCredentials
}

// MARK: - QrzCallbookClient

/// Thin Swift facade over the shared Rust `QrzApi` (cw-net `QrzClient`) for QRZ
/// XML callbook lookups. The session-key auth, XML parse, and alias/previous-call
/// logic live entirely in Rust — identical to the Android client and parity-tested
/// against the old Swift implementation it replaces.
///
/// Credentials are the user-facing `qrz.callbook.*` Keychain keys written by the
/// Settings UI. This client bridges them into the FFI's own secure-store namespace
/// (`cw.qrz.*`) via `setCredentials` whenever they change, so the user-facing keys
/// stay the single source of truth and changing them in Settings takes effect on
/// the next lookup without a relaunch.
///
/// Mirrors the `OAuthClient` template: an `actor` holding a lazily-built `QrzApi`
/// over a Keychain-backed `SecureStore`. `QrzApi` keeps its own in-memory session
/// and single-flight re-auth, so callers can issue many lookups (e.g. the grid
/// batch repair) without managing a session key.
actor QrzCallbookClient {
    // MARK: Internal

    /// Look up `callsign` in the QRZ callbook. Returns `nil` when QRZ has no
    /// record. Throws ``QrzCallbookError/noCredentials`` when the user hasn't
    /// signed in, or a `CwError` (`.Auth`/`.Network`) on failure.
    func lookup(_ callsign: String) async throws -> FfiQrzLookup? {
        guard
            let username = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookUsername
            ),
            let password = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookPassword
            ),
            !username.isEmpty, !password.isEmpty
        else {
            throw QrzCallbookError.noCredentials
        }

        let api = try resolvedAPI()
        // Keep the FFI secure-store namespace in sync with the canonical
        // `qrz.callbook.*` keys, writing only when they actually change.
        if syncedCredentials?.username != username
            || syncedCredentials?.password != password
        {
            api.setCredentials(username: username, password: password)
            syncedCredentials = (username, password)
        }

        return try await api.lookup(callsign: callsign)
    }

    // MARK: Private

    private var api: QrzApi?
    private var syncedCredentials: (username: String, password: String)?

    /// Lazily build the Rust `QrzApi` over the Keychain-backed secure store.
    private func resolvedAPI() throws -> QrzApi {
        if let api {
            return api
        }
        let created = try QrzApi(secure: KeychainSecureStore())
        api = created
        return created
    }
}
