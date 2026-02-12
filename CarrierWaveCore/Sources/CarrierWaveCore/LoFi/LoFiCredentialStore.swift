import Foundation

// MARK: - LoFiCredentialKey

public enum LoFiCredentialKey: String, Sendable, CaseIterable {
    case authToken = "lofi.auth.token"
    case clientKey = "lofi.client.key"
    case clientSecret = "lofi.client.secret"
    case callsign = "lofi.callsign"
    case email = "lofi.email"
    case deviceLinked = "lofi.device.linked"
    case lastSyncMillis = "lofi.last.sync.millis"
    case syncFlags = "lofi.sync.flags"
}

// MARK: - LoFiCredentialStore

public protocol LoFiCredentialStore: Sendable {
    func getString(_ key: LoFiCredentialKey) throws -> String
    func setString(_ value: String, for key: LoFiCredentialKey) throws
    func getData(_ key: LoFiCredentialKey) throws -> Data
    func setData(_ value: Data, for key: LoFiCredentialKey) throws
    func delete(_ key: LoFiCredentialKey) throws
}
