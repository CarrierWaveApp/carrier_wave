import Foundation

// MARK: - ConnectorType

/// RF connector types used on radios and antennas.
public enum ConnectorType: String, Codable, Sendable, CaseIterable, Identifiable {
    case bnc = "BNC"
    case so239 = "SO-239"
    case sma = "SMA"
    case nType = "N-Type"

    // MARK: Public

    public var id: String {
        rawValue
    }

    /// The coax/cable label for this connector.
    public var coaxLabel: String {
        switch self {
        case .bnc: "BNC coax"
        case .so239: "PL-259 coax"
        case .sma: "SMA coax"
        case .nType: "N-Type coax"
        }
    }
}

// MARK: - GearConnectorStorage

/// Persists connector type per equipment name via iCloud KVS.
///
/// Keyed by equipment name so the connector tag follows the gear
/// across sessions. When the user tags their KX2 as BNC once, it
/// stays BNC until changed.
public enum GearConnectorStorage {
    // MARK: Public

    public static func connector(for name: String) -> ConnectorType? {
        let map = loadMap()
        return map[name]
    }

    public static func setConnector(
        _ type: ConnectorType?,
        for name: String
    ) {
        var map = loadMap()
        map[name] = type
        saveMap(map)
    }

    // MARK: Private

    private static let storageKey = "gearConnectorMap"
    private static let kvs = NSUbiquitousKeyValueStore.default

    private static func loadMap() -> [String: ConnectorType] {
        guard let data = kvs.data(forKey: storageKey),
              let map = try? JSONDecoder().decode(
                  [String: ConnectorType].self,
                  from: data
              )
        else {
            return [:]
        }
        return map
    }

    private static func saveMap(_ map: [String: ConnectorType]) {
        guard let data = try? JSONEncoder().encode(map) else {
            return
        }
        kvs.set(data, forKey: storageKey)
        kvs.synchronize()
    }
}

// MARK: - GearReminder

/// A contextual reminder generated from the selected equipment combo.
public struct GearReminder: Identifiable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(id: String, text: String, icon: String) {
        self.id = id
        self.text = text
        self.icon = icon
    }

    // MARK: Public

    /// Deterministic ID for stable identity across regenerations.
    public let id: String
    public let text: String
    public let icon: String
}

// MARK: - GearReminderEngine

/// Generates contextual "don't forget" reminders based on selected
/// equipment, connector types, and operating mode.
public enum GearReminderEngine {
    // MARK: Public

    /// Build reminders for the current equipment combination.
    ///
    /// - Parameters:
    ///   - radioConnector: Connector on the selected radio (nil if untagged).
    ///   - antennaConnector: Connector on the selected antenna (nil if untagged).
    ///   - mode: Operating mode (CW, SSB, FT8, etc.).
    ///   - hasAntenna: Whether an antenna is selected.
    ///   - hasKey: Whether a CW key is selected.
    public static func generate(
        radioConnector: ConnectorType?,
        antennaConnector: ConnectorType?,
        mode: String,
        hasAntenna: Bool,
        hasKey: Bool
    ) -> [GearReminder] {
        var result: [GearReminder] = []
        appendConnectorReminders(
            radio: radioConnector,
            antenna: antennaConnector,
            to: &result
        )
        appendAntennaReminders(hasAntenna: hasAntenna, to: &result)
        appendPowerReminders(to: &result)
        appendModeReminders(mode: mode, hasKey: hasKey, to: &result)
        appendGeneralReminders(to: &result)
        return result
    }

    // MARK: Private

    // MARK: - Connector

    private static func appendConnectorReminders(
        radio: ConnectorType?,
        antenna: ConnectorType?,
        to result: inout [GearReminder]
    ) {
        switch (radio, antenna) {
        case let (.some(rc), .some(ac)) where rc == ac:
            result.append(GearReminder(
                id: "coax-\(rc.rawValue)",
                text: rc.coaxLabel,
                icon: "cable.connector"
            ))
        case let (.some(rc), .some(ac)):
            result.append(GearReminder(
                id: "adapter-\(rc.rawValue)-\(ac.rawValue)",
                text: "\(rc.rawValue)-to-\(ac.rawValue) adapter",
                icon: "arrow.triangle.swap"
            ))
            result.append(GearReminder(
                id: "coax-\(ac.rawValue)",
                text: "\(ac.coaxLabel) (antenna side)",
                icon: "cable.connector"
            ))
        case let (.some(rc), .none):
            result.append(GearReminder(
                id: "coax-\(rc.rawValue)",
                text: rc.coaxLabel,
                icon: "cable.connector"
            ))
        case let (.none, .some(ac)):
            result.append(GearReminder(
                id: "coax-\(ac.rawValue)",
                text: ac.coaxLabel,
                icon: "cable.connector"
            ))
        case (.none, .none):
            break
        }
    }

    // MARK: - Antenna

    private static func appendAntennaReminders(
        hasAntenna: Bool,
        to result: inout [GearReminder]
    ) {
        guard hasAntenna else {
            return
        }
        result.append(GearReminder(
            id: "counterpoise",
            text: "Counterpoise / radials",
            icon: "line.diagonal"
        ))
        result.append(GearReminder(
            id: "mast",
            text: "Antenna support / mast",
            icon: "arrow.up.to.line"
        ))
        result.append(GearReminder(
            id: "guy-lines",
            text: "Guy lines & stakes",
            icon: "tent"
        ))
    }

    // MARK: - Power

    private static func appendPowerReminders(
        to result: inout [GearReminder]
    ) {
        result.append(GearReminder(
            id: "power-cable",
            text: "Power cable",
            icon: "bolt"
        ))
        result.append(GearReminder(
            id: "battery",
            text: "Battery / power supply",
            icon: "battery.100"
        ))
    }

    // MARK: - Mode-specific

    private static func appendModeReminders(
        mode: String,
        hasKey: Bool,
        to result: inout [GearReminder]
    ) {
        if mode == "CW", hasKey {
            result.append(GearReminder(
                id: "key-cable",
                text: "Paddle cable (1/4″ or 3.5mm)",
                icon: "cable.connector"
            ))
        }
        let voiceModes: Set = ["SSB", "USB", "LSB", "AM", "FM"]
        if voiceModes.contains(mode) {
            result.append(GearReminder(
                id: "mic-cable",
                text: "Mic cable / adapter",
                icon: "cable.connector"
            ))
        }
        let digiModes: Set = ["FT8", "FT4", "JTTY", "DIGITAL"]
        if digiModes.contains(mode) {
            result.append(GearReminder(
                id: "audio-interface",
                text: "Audio interface / USB cable",
                icon: "cable.connector"
            ))
        }
    }

    // MARK: - General

    private static func appendGeneralReminders(
        to result: inout [GearReminder]
    ) {
        result.append(GearReminder(
            id: "headphones",
            text: "Headphones",
            icon: "headphones"
        ))
    }
}
