import CarrierWaveCore
import Foundation

// MARK: - KeychainSecureStore

/// Host implementation of the Rust `SecureStore` foreign trait, backed by the
/// Keychain. The shared `AuthApi` (cw-net OAuth) drives the protocol and calls
/// back into this to persist the rotating refresh token and the in-flight PKCE
/// verifier — the Android equivalent is `AndroidSecureStore`
/// (EncryptedSharedPreferences). Stateless, so trivially `Sendable` as the
/// foreign trait requires.
public final class KeychainSecureStore: SecureStore, Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public func get(key: String) -> String? {
        try? KeychainHelper.shared.readString(for: key)
    }

    public func set(key: String, value: String) {
        try? KeychainHelper.shared.save(value, for: key)
    }

    public func delete(key: String) {
        try? KeychainHelper.shared.delete(for: key)
    }
}
