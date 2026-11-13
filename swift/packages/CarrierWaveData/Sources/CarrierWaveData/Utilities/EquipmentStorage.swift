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

    // MARK: Private

    private static let kvs = NSUbiquitousKeyValueStore.default
}
