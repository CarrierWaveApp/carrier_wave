import CarrierWaveCore
import Foundation

// MARK: - FileCredentialStore

/// LoFiCredentialStore backed by ~/.config/lofi-cli/credentials.json
struct FileCredentialStore: LoFiCredentialStore {
    // MARK: Lifecycle

    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lofi-cli")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        fileURL = configDir.appendingPathComponent("credentials.json")
    }

    // MARK: Internal

    func getString(_ key: LoFiCredentialKey) throws -> String {
        let store = try loadStore()
        guard let value = store[key.rawValue] else {
            throw FileCredentialError.keyNotFound(key.rawValue)
        }
        return value
    }

    func setString(_ value: String, for key: LoFiCredentialKey) throws {
        var store = (try? loadStore()) ?? [:]
        store[key.rawValue] = value
        try saveStore(store)
    }

    func getData(_ key: LoFiCredentialKey) throws -> Data {
        let base64 = try getString(key)
        guard let data = Data(base64Encoded: base64) else {
            throw FileCredentialError.invalidData
        }
        return data
    }

    func setData(_ value: Data, for key: LoFiCredentialKey) throws {
        try setString(value.base64EncodedString(), for: key)
    }

    func delete(_ key: LoFiCredentialKey) throws {
        var store = (try? loadStore()) ?? [:]
        store.removeValue(forKey: key.rawValue)
        try saveStore(store)
    }

    // MARK: Private

    private let fileURL: URL

    private func loadStore() throws -> [String: String] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func saveStore(_ store: [String: String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - FileCredentialError

enum FileCredentialError: Error, LocalizedError {
    case keyNotFound(String)
    case invalidData

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .keyNotFound(key):
            "Credential not found: \(key)"
        case .invalidData:
            "Invalid credential data"
        }
    }
}
