import Foundation

// MARK: - EquipmentType

/// Types of equipment that can be saved in user-managed lists.
/// Shared between Carrier Wave (iOS) and CW Sweep (macOS) via iCloud KVS.
public enum EquipmentType: String, Sendable {
    case antenna = "userAntennaList"
    case key = "userKeyList"
    case mic = "userMicList"

    // MARK: Public

    public var displayName: String {
        switch self {
        case .antenna: "Antenna"
        case .key: "Key"
        case .mic: "Microphone"
        }
    }

    public var icon: String {
        switch self {
        case .antenna: "antenna.radiowaves.left.and.right"
        case .key: "pianokeys"
        case .mic: "mic"
        }
    }

    public var addPrompt: String {
        switch self {
        case .antenna: "Antenna name"
        case .key: "Key name"
        case .mic: "Microphone name"
        }
    }
}

// MARK: - EquipmentStorage

/// Equipment list storage backed by iCloud Key-Value Store for
/// cross-device sync between Carrier Wave (iOS) and CW Sweep (macOS).
/// Falls back to UserDefaults on platforms without iCloud KVS.
public enum EquipmentStorage {
    // MARK: Public

    public static func load(for type: EquipmentType) -> [String] {
        kvs.array(forKey: type.rawValue) as? [String] ?? []
    }

    public static func add(_ name: String, for type: EquipmentType) {
        var items = load(for: type)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !items.contains(trimmed) else {
            return
        }
        items.append(trimmed)
        items.sort(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        kvs.set(items, forKey: type.rawValue)
        kvs.synchronize()
    }

    public static func remove(_ name: String, for type: EquipmentType) {
        var items = load(for: type)
        items.removeAll { $0 == name }
        kvs.set(items, forKey: type.rawValue)
        kvs.synchronize()
    }

    /// Test seam: route reads and writes to `store` (e.g. an isolated
    /// `UserDefaults` suite) instead of iCloud KVS, so tests never touch the
    /// user's synced lists. Pass `nil` to restore iCloud KVS.
    public static func overrideStore(_ store: EquipmentKeyValueStore?) {
        storeOverride.set(store)
    }

    // MARK: Private

    /// NSLock-guarded override (no `nonisolated(unsafe)` on mutable state).
    private final class OverrideHolder: @unchecked Sendable {
        // MARK: Internal

        func set(_ value: EquipmentKeyValueStore?) {
            lock.withLock { self.value = value }
        }

        func get() -> EquipmentKeyValueStore? {
            lock.withLock { value }
        }

        // MARK: Private

        private let lock = NSLock()
        private var value: EquipmentKeyValueStore?
    }

    private static let storeOverride = OverrideHolder()

    private static var kvs: EquipmentKeyValueStore {
        storeOverride.get() ?? NSUbiquitousKeyValueStore.default
    }
}

// MARK: - EquipmentKeyValueStore

/// The slice of `NSUbiquitousKeyValueStore` / `UserDefaults` that
/// `EquipmentStorage` uses.
public protocol EquipmentKeyValueStore: AnyObject {
    func array(forKey key: String) -> [Any]?
    func set(_ value: Any?, forKey key: String)
    @discardableResult
    func synchronize() -> Bool
}

// MARK: - NSUbiquitousKeyValueStore + EquipmentKeyValueStore

extension NSUbiquitousKeyValueStore: EquipmentKeyValueStore {}

// MARK: - UserDefaults + EquipmentKeyValueStore

extension UserDefaults: EquipmentKeyValueStore {}
