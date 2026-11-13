import CarrierWaveData
import Foundation
import Security

extension KeychainHelper {
    /// One-time migration: copies all existing eligible credentials to the shared group.
    /// Skips entirely after the first successful run (checked via UserDefaults flag).
    nonisolated func migrateExistingToSharedGroup() {
        if UserDefaults.standard.bool(forKey: "sharedGroupMigrationComplete") {
            return
        }

        let keysToMigrate: [String] = [
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

        var migrated = 0
        var failed = 0
        for key in keysToMigrate {
            guard let data = try? read(for: key) else {
                continue
            }
            if migrateKeyToSharedGroup(key: key, data: data) {
                migrated += 1
            } else {
                failed += 1
            }
        }
        #if DEBUG
            print("[Keychain] shared group migration: \(migrated) migrated, \(failed) failed")
        #endif
        UserDefaults.standard.set(true, forKey: "sharedGroupMigrationComplete")
    }

    /// Migrate a single key's data to the shared iCloud Keychain group.
    /// Returns `true` on success.
    nonisolated private func migrateKeyToSharedGroup(key: String, data: Data) -> Bool {
        let sharedService = "com.fullduplex.shared"
        let sharedAccessGroup = "7UE4RDLUSX.com.fullduplex.shared"

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
        if status != errSecSuccess {
            #if DEBUG
                print("[Keychain] shared group write failed for \(key): \(status)")
            #endif
            return false
        }
        return true
    }
}
