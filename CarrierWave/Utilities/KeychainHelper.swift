import Foundation
import Security

// MARK: - KeychainError

enum KeychainError: Error, Sendable {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData
}

// MARK: - KeychainHelper

/// Thread-safe keychain access helper.
/// Keychain APIs are thread-safe at the OS level, so this type is safe to use from any context.
/// All methods are nonisolated since Security framework APIs are thread-safe.
struct KeychainHelper: Sendable {
    // MARK: Lifecycle

    nonisolated private init() {}

    // MARK: Internal

    // swiftformat:disable:next redundantNonisolated
    nonisolated static let shared = KeychainHelper()

    nonisolated func save(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        // Mirror eligible credentials to shared group for cross-app sync
        if Self.sharedKeys.contains(key) {
            try? saveToSharedGroup(data, for: key)
        }
    }

    nonisolated func save(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data, for: key)
    }

    nonisolated func read(for key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    nonisolated func readString(for key: String) throws -> String {
        let data = try read(for: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    nonisolated func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }

        // Remove from shared group if this was a mirrored key
        if Self.sharedKeys.contains(key) {
            try? deleteFromSharedGroup(for: key)
        }
    }

    /// One-time migration: copies all existing eligible credentials to the shared group.
    /// Safe to call multiple times — writes are idempotent (delete-then-add).
    nonisolated func migrateExistingToSharedGroup() {
        var migrated = 0
        var failed = 0
        for key in Self.sharedKeys {
            guard let data = try? read(for: key) else {
                continue
            }
            do {
                try saveToSharedGroup(data, for: key)
                migrated += 1
            } catch {
                failed += 1
                print("[Keychain] shared group write failed for \(key): \(error)")
            }
        }
        print("[Keychain] shared group migration: \(migrated) migrated, \(failed) failed")
    }

    // MARK: Private

    // Credential keys that are automatically mirrored to the shared keychain group.
    // Ephemeral keys (session tokens, counters, timestamps, progress) are excluded.
    // swiftformat:disable:next redundantNonisolated
    nonisolated private static let sharedKeys: Set<String> = [
        // QRZ Logbook
        Keys.qrzApiKey, Keys.qrzCallsign,
        // QRZ Callbook
        Keys.qrzCallbookUsername, Keys.qrzCallbookPassword,
        // POTA
        Keys.potaUsername, Keys.potaPassword,
        // LoFi
        Keys.lofiAuthToken, Keys.lofiClientKey, Keys.lofiClientSecret,
        Keys.lofiCallsign, Keys.lofiEmail,
        // HAMRS
        Keys.hamrsApiKey,
        // Activities
        Keys.activitiesAuthToken,
        // LoTW
        Keys.lotwUsername, Keys.lotwPassword,
        // Club Log
        Keys.clublogApiKey, Keys.clublogEmail,
        Keys.clublogPassword, Keys.clublogCallsign,
        // User identity
        Keys.currentCallsign, Keys.previousCallsigns, Keys.userProfile,
    ]

    private let service = "com.fullduplex.credentials"

    /// Shared keychain service for cross-app credential sync via iCloud Keychain.
    private let sharedService = "com.fullduplex.shared"
    private let sharedAccessGroup = "7UE4RDLUSX.com.fullduplex.shared"

    /// Mirrors a credential to the shared keychain group with iCloud Keychain sync.
    /// Uses `try?` at call sites so local saves always succeed even if this fails.
    nonisolated private func saveToSharedGroup(_ data: Data, for key: String) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sharedService,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: sharedAccessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sharedService,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: sharedAccessGroup,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes a credential from the shared keychain group.
    nonisolated private func deleteFromSharedGroup(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sharedService,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: sharedAccessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: KeychainHelper.Keys

/// Keychain keys for each service
/// All keys are nonisolated to allow access from any actor context
extension KeychainHelper {
    // swiftformat:disable redundantNonisolated
    enum Keys: Sendable {
        // QRZ - token-based auth (new)
        nonisolated static let qrzApiKey = "qrz.api.key"
        nonisolated static let qrzCallsign = "qrz.callsign"
        nonisolated static let qrzBookIdMap = "qrz.bookid.map" // JSON: {callsign: bookId}
        nonisolated static let qrzTotalUploaded = "qrz.total.uploaded"
        nonisolated static let qrzTotalDownloaded = "qrz.total.downloaded"
        nonisolated static let qrzLastUploadDate = "qrz.last.upload.date"
        nonisolated static let qrzLastDownloadDate = "qrz.last.download.date"

        // QRZ XML Callbook - username/password auth for callsign lookups
        // This is separate from the Logbook API key - requires QRZ XML subscription
        nonisolated static let qrzCallbookUsername = "qrz.callbook.username"
        nonisolated static let qrzCallbookPassword = "qrz.callbook.password"
        nonisolated static let qrzCallbookSessionKey = "qrz.callbook.session.key"

        // QRZ - session-based auth (deprecated, remove after migration)
        nonisolated static let qrzSessionKey = "qrz.session.key"
        nonisolated static let qrzUsername = "qrz.username"

        // POTA
        nonisolated static let potaIdToken = "pota.id.token"
        nonisolated static let potaTokenExpiry = "pota.token.expiry"
        nonisolated static let potaUsername = "pota.username"
        nonisolated static let potaPassword = "pota.password"
        nonisolated static let potaDownloadProgress = "pota.download.progress" // JSON checkpoint
        nonisolated static let potaLastSyncDate = "pota.last.sync.date"

        // LoFi
        nonisolated static let lofiAuthToken = "lofi.auth.token"
        nonisolated static let lofiClientKey = "lofi.client.key"
        nonisolated static let lofiClientSecret = "lofi.client.secret"
        nonisolated static let lofiCallsign = "lofi.callsign"
        nonisolated static let lofiEmail = "lofi.email"
        nonisolated static let lofiDeviceLinked = "lofi.device.linked"
        nonisolated static let lofiLastSyncMillis = "lofi.last.sync.millis"
        nonisolated static let lofiSyncFlags = "lofi.sync.flags" // JSON LoFiSyncFlags

        /// HAMRS
        nonisolated static let hamrsApiKey = "hamrs.api.key"

        /// Activities
        nonisolated static let activitiesAuthToken = "challenges.auth.token"

        /// LoTW
        nonisolated static let lotwUsername = "lotw.username"
        nonisolated static let lotwPassword = "lotw.password"
        nonisolated static let lotwLastQSL = "lotw.last.qsl"
        nonisolated static let lotwLastQSORx = "lotw.last.qso.rx"

        /// Club Log
        nonisolated static let clublogApiKey = "clublog.api.key"
        nonisolated static let clublogEmail = "clublog.email"
        nonisolated static let clublogPassword = "clublog.password"
        nonisolated static let clublogCallsign = "clublog.callsign"
        nonisolated static let clublogLastDownloadDate = "clublog.last.download.date"

        /// Callsign Aliases
        nonisolated static let currentCallsign = "user.current.callsign"
        nonisolated static let previousCallsigns = "user.previous.callsigns" // JSON array

        /// User Profile
        nonisolated static let userProfile = "user.profile" // JSON UserProfile
    }
    // swiftformat:enable redundantNonisolated
}
