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
    }

    // MARK: Private

    private let service = "com.fullduplex.credentials"
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

        /// Callsign Aliases
        nonisolated static let currentCallsign = "user.current.callsign"
        nonisolated static let previousCallsigns = "user.previous.callsigns" // JSON array

        /// User Profile
        nonisolated static let userProfile = "user.profile" // JSON UserProfile
    }
    // swiftformat:enable redundantNonisolated
}
