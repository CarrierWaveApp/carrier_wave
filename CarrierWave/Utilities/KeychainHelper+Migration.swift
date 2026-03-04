import CarrierWaveData
import Security

extension KeychainHelper {
    /// One-time migration: copies all existing eligible credentials to the shared group.
    /// Safe to call multiple times — writes are idempotent (delete-then-add).
    nonisolated func migrateExistingToSharedGroup() {
        let sharedService = "com.fullduplex.shared"
        let sharedAccessGroup = "7UE4RDLUSX.com.fullduplex.shared"

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
            do {
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
                migrated += 1
            } catch {
                failed += 1
                print("[Keychain] shared group write failed for \(key): \(error)")
            }
        }
        print("[Keychain] shared group migration: \(migrated) migrated, \(failed) failed")
    }
}
