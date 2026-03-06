import Foundation
import Security

// MARK: - KeychainError

public enum KeychainError: Error, Sendable {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData
}

// MARK: - KeychainHelper

/// Thread-safe keychain access helper.
/// Keychain APIs are thread-safe at the OS level.
public struct KeychainHelper: Sendable {
    // MARK: Lifecycle

    nonisolated private init() {}

    // MARK: Public

    // swiftformat:disable:next redundantNonisolated
    nonisolated public static let shared = KeychainHelper()

    nonisolated public func save(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        if Self.sharedKeys.contains(key) {
            try? saveToSharedGroup(data, for: key)
        }
    }

    nonisolated public func save(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data, for: key)
    }

    nonisolated public func read(for key: String) throws -> Data {
        // Try shared group first (cross-app credentials from iCloud Keychain)
        if Self.sharedKeys.contains(key),
           let sharedData = try? readFromSharedGroup(for: key)
        {
            return sharedData
        }

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

    nonisolated public func readString(for key: String) throws -> String {
        let data = try read(for: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    nonisolated public func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }

        if Self.sharedKeys.contains(key) {
            try? deleteFromSharedGroup(for: key)
        }
    }

    // MARK: Private

    // swiftformat:disable:next redundantNonisolated
    nonisolated private static let sharedKeys: Set<String> = [
        Keys.qrzApiKey, Keys.qrzCallsign,
        Keys.qrzCallbookUsername, Keys.qrzCallbookPassword,
        Keys.potaUsername, Keys.potaPassword,
        Keys.lofiAuthToken, Keys.lofiClientKey, Keys.lofiClientSecret,
        Keys.lofiCallsign, Keys.lofiEmail,
        Keys.hamrsApiKey,
        Keys.activitiesAuthToken,
        Keys.lotwUsername, Keys.lotwPassword,
        Keys.clublogApiKey, Keys.clublogEmail,
        Keys.clublogPassword, Keys.clublogCallsign,
        Keys.currentCallsign, Keys.previousCallsigns, Keys.userProfile,
    ]

    private let service = "com.fullduplex.credentials"
    private let sharedService = "com.fullduplex.shared"
    private let sharedAccessGroup = "7UE4RDLUSX.com.fullduplex.shared"

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

    nonisolated private func readFromSharedGroup(for key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sharedService,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: sharedAccessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.itemNotFound
        }

        return data
    }

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

public extension KeychainHelper {
    // swiftformat:disable redundantNonisolated
    enum Keys: Sendable {
        // QRZ
        nonisolated public static let qrzApiKey = "qrz.api.key"
        nonisolated public static let qrzCallsign = "qrz.callsign"
        nonisolated public static let qrzBookIdMap = "qrz.bookid.map"
        nonisolated public static let qrzTotalUploaded = "qrz.total.uploaded"
        nonisolated public static let qrzTotalDownloaded = "qrz.total.downloaded"
        nonisolated public static let qrzLastUploadDate = "qrz.last.upload.date"
        nonisolated public static let qrzLastDownloadDate = "qrz.last.download.date"

        // QRZ XML Callbook
        nonisolated public static let qrzCallbookUsername = "qrz.callbook.username"
        nonisolated public static let qrzCallbookPassword = "qrz.callbook.password"
        nonisolated public static let qrzCallbookSessionKey = "qrz.callbook.session.key"

        // QRZ legacy
        nonisolated public static let qrzSessionKey = "qrz.session.key"
        nonisolated public static let qrzUsername = "qrz.username"

        // POTA
        nonisolated public static let potaIdToken = "pota.id.token"
        nonisolated public static let potaTokenExpiry = "pota.token.expiry"
        nonisolated public static let potaUsername = "pota.username"
        nonisolated public static let potaPassword = "pota.password"
        nonisolated public static let potaDownloadProgress = "pota.download.progress"
        nonisolated public static let potaLastSyncDate = "pota.last.sync.date"

        // LoFi
        nonisolated public static let lofiAuthToken = "lofi.auth.token"
        nonisolated public static let lofiClientKey = "lofi.client.key"
        nonisolated public static let lofiClientSecret = "lofi.client.secret"
        nonisolated public static let lofiCallsign = "lofi.callsign"
        nonisolated public static let lofiEmail = "lofi.email"
        nonisolated public static let lofiDeviceLinked = "lofi.device.linked"
        nonisolated public static let lofiLastSyncMillis = "lofi.last.sync.millis"
        nonisolated public static let lofiSyncFlags = "lofi.sync.flags"

        /// HAMRS
        nonisolated public static let hamrsApiKey = "hamrs.api.key"

        /// Activities
        nonisolated public static let activitiesAuthToken = "challenges.auth.token"

        // LoTW
        nonisolated public static let lotwUsername = "lotw.username"
        nonisolated public static let lotwPassword = "lotw.password"
        nonisolated public static let lotwLastQSL = "lotw.last.qsl"
        nonisolated public static let lotwLastQSORx = "lotw.last.qso.rx"

        // Club Log
        nonisolated public static let clublogApiKey = "clublog.api.key"
        nonisolated public static let clublogEmail = "clublog.email"
        nonisolated public static let clublogPassword = "clublog.password"
        nonisolated public static let clublogCallsign = "clublog.callsign"
        nonisolated public static let clublogLastDownloadDate = "clublog.last.download.date"

        // User Identity
        nonisolated public static let currentCallsign = "user.current.callsign"
        nonisolated public static let previousCallsigns = "user.previous.callsigns"
        nonisolated public static let userProfile = "user.profile"
    }
    // swiftformat:enable redundantNonisolated
}
