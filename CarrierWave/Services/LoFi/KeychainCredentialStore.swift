import CarrierWaveCore
import Foundation

/// Adapts KeychainHelper to the LoFiCredentialStore protocol
struct KeychainCredentialStore: LoFiCredentialStore {
    // MARK: Internal

    func getString(_ key: LoFiCredentialKey) throws -> String {
        try keychain.readString(for: key.rawValue)
    }

    func setString(_ value: String, for key: LoFiCredentialKey) throws {
        try keychain.save(value, for: key.rawValue)
    }

    func getData(_ key: LoFiCredentialKey) throws -> Data {
        try keychain.read(for: key.rawValue)
    }

    func setData(_ value: Data, for key: LoFiCredentialKey) throws {
        try keychain.save(value, for: key.rawValue)
    }

    func delete(_ key: LoFiCredentialKey) throws {
        try keychain.delete(for: key.rawValue)
    }

    // MARK: Private

    private let keychain = KeychainHelper.shared
}
