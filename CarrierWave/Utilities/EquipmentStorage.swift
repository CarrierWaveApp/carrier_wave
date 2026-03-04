import CarrierWaveData
import Foundation

// MARK: - EquipmentType

/// Types of equipment that can be saved in user-managed lists
enum EquipmentType: String {
    case antenna = "userAntennaList"
    case key = "userKeyList"
    case mic = "userMicList"

    // MARK: Internal

    var displayName: String {
        switch self {
        case .antenna: "Antenna"
        case .key: "Key"
        case .mic: "Microphone"
        }
    }

    var icon: String {
        switch self {
        case .antenna: "antenna.radiowaves.left.and.right"
        case .key: "pianokeys"
        case .mic: "mic"
        }
    }

    var addPrompt: String {
        switch self {
        case .antenna: "Antenna name"
        case .key: "Key name"
        case .mic: "Microphone name"
        }
    }
}

// MARK: - EquipmentStorage

/// Generic UserDefaults-backed storage for user equipment lists
enum EquipmentStorage {
    static func load(for type: EquipmentType) -> [String] {
        UserDefaults.standard.stringArray(forKey: type.rawValue) ?? []
    }

    static func add(_ name: String, for type: EquipmentType) {
        var items = load(for: type)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !items.contains(trimmed) else {
            return
        }
        items.append(trimmed)
        items.sort(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        UserDefaults.standard.set(items, forKey: type.rawValue)
    }

    static func remove(_ name: String, for type: EquipmentType) {
        var items = load(for: type)
        items.removeAll { $0 == name }
        UserDefaults.standard.set(items, forKey: type.rawValue)
    }
}
