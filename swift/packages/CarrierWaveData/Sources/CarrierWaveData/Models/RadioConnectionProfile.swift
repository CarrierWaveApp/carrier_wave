import Foundation

// MARK: - RadioTransportKind

/// Wire transport for a radio connection.
///
/// Lives in CarrierWaveData (not the iOS target) so the data layer can
/// persist a connection profile without depending on iOS types. Raw
/// values match `RadioService.TransportType` so iOS can translate
/// trivially.
public enum RadioTransportKind: String, Codable, Sendable, CaseIterable {
    case ble
    case wifi
    case flex
    case scuLan10

    // MARK: Public

    public var displayName: String {
        switch self {
        case .ble: "Bluetooth"
        case .wifi: "Wi-Fi"
        case .flex: "FlexRadio"
        case .scuLan10: "SCU-LAN10"
        }
    }
}

// MARK: - RadioProtocolKind

/// CAT protocol family for a radio. Mirrors the iOS `RigProtocol`
/// enum but lives in shared data so catalog metadata can declare it.
public enum RadioProtocolKind: String, Codable, Sendable, CaseIterable {
    case civ
    case kenwood

    // MARK: Public

    public var displayName: String {
        switch self {
        case .civ: "CI-V (Icom)"
        case .kenwood: "Kenwood/Elecraft"
        }
    }
}

// MARK: - RadioConnectionProfile

/// Per-item connection configuration.
///
/// Stored on `EquipmentItem.connectionProfileJSON`. Replaces the global
/// `UserDefaults`-backed radio settings: the same IC-705 can have
/// different profiles per device, and a session that selects a
/// configured radio item can auto-connect on start.
///
/// Credentials live in Keychain, keyed by `keychainCredentialRef`
/// (typically the equipment item UUID).
public struct RadioConnectionProfile: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        transport: RadioTransportKind,
        protocolKind: RadioProtocolKind? = nil,
        bleDeviceUUID: UUID? = nil,
        bleDeviceName: String? = nil,
        bleViaBridge: Bool = false,
        hostAddress: String? = nil,
        port: Int? = nil,
        civAddress: UInt8? = nil,
        flexSliceIndex: Int? = nil,
        useSmartLink: Bool = false,
        keychainCredentialRef: String? = nil
    ) {
        self.transport = transport
        self.protocolKind = protocolKind
        self.bleDeviceUUID = bleDeviceUUID
        self.bleDeviceName = bleDeviceName
        self.bleViaBridge = bleViaBridge
        self.hostAddress = hostAddress
        self.port = port
        self.civAddress = civAddress
        self.flexSliceIndex = flexSliceIndex
        self.useSmartLink = useSmartLink
        self.keychainCredentialRef = keychainCredentialRef
    }

    // MARK: Public

    public var transport: RadioTransportKind

    /// Explicit protocol override. When nil, callers derive from the
    /// catalog entry or by sniffing the rig name.
    public var protocolKind: RadioProtocolKind?

    // BLE
    public var bleDeviceUUID: UUID?
    public var bleDeviceName: String?
    /// When true, the BLE connection is routed through a CW Bridge that
    /// then forwards CAT to the radio.
    public var bleViaBridge: Bool

    // WiFi (Icom RS-BA1) and Flex (SmartSDR TCP)
    public var hostAddress: String?
    public var port: Int?

    /// CI-V address (used by WiFi/RS-BA1)
    public var civAddress: UInt8?

    /// Flex slice
    public var flexSliceIndex: Int?

    /// Whether Flex should connect via SmartLink (WAN) instead of LAN.
    public var useSmartLink: Bool

    /// Identifier used to look up auth credentials in Keychain.
    /// Conventionally the owning `EquipmentItem.id.uuidString`.
    public var keychainCredentialRef: String?

    /// Whether the profile carries enough info to attempt a connection.
    public var isConfigured: Bool {
        switch transport {
        case .ble:
            bleDeviceUUID != nil
        case .wifi,
             .flex,
             .scuLan10:
            !(hostAddress ?? "").isEmpty
        }
    }

    /// A short, human-readable summary for the equipment detail row.
    public var summary: String {
        switch transport {
        case .ble:
            let name = bleDeviceName ?? "Bluetooth"
            return bleViaBridge ? "via CW Bridge — \(name)" : "BLE — \(name)"
        case .wifi:
            return "Wi-Fi — \(hostAddress ?? "Not set")"
        case .flex:
            let host = hostAddress ?? "Not set"
            return useSmartLink ? "SmartLink — \(host)" : "Flex — \(host)"
        case .scuLan10:
            return "SCU-LAN10 — \(hostAddress ?? "Not set")"
        }
    }
}

// MARK: - RadioCatalogMetadata

/// Derived catalog metadata for radios: protocol, supported transports,
/// CW Bridge compatibility.
///
/// The activities server catalog does not yet ship these fields. Until
/// it does, this helper infers them from the manufacturer + model name.
/// Returns nil for non-radio categories so callers can branch cleanly.
public enum RadioCatalogMetadata {
    // MARK: Public

    public static let cwBridgeCatalogId = "carrierwave-cw-bridge"

    /// Whether the slug identifies the CW Bridge accessory itself.
    public static func isCWBridge(catalogId: String) -> Bool {
        catalogId == cwBridgeCatalogId
    }

    /// Best-guess radio protocol from manufacturer + model.
    public static func protocolKind(for entry: CatalogEntry) -> RadioProtocolKind? {
        protocolKind(manufacturer: entry.manufacturer, name: entry.name)
    }

    public static func protocolKind(
        manufacturer: String,
        name: String
    ) -> RadioProtocolKind? {
        let normalized = normalize(manufacturer + " " + name)
        if civKeywords.contains(where: { normalized.contains($0) }) {
            return .civ
        }
        if kenwoodKeywords.contains(where: { normalized.contains($0) }) {
            return .kenwood
        }
        if name.lowercased().hasPrefix("ic-") || name.lowercased().hasPrefix("ic") {
            return .civ
        }
        return nil
    }

    /// Transports this radio plausibly supports. Conservative default
    /// is BLE-only via the bridge — works for any radio with a CAT port.
    public static func supportedTransports(for entry: CatalogEntry) -> [RadioTransportKind] {
        let normalized = normalize(entry.manufacturer + " " + entry.name)
        if normalized.contains("flex") {
            return [.flex]
        }
        // Icom networked rigs (RS-BA1)
        if normalized.contains("ic7610") || normalized.contains("ic705")
            || normalized.contains("ic9700") || normalized.contains("ic905")
        {
            return [.ble, .wifi]
        }
        // Everything else — assume BLE (via CW Bridge)
        return entry.category == .radio ? [.ble] : []
    }

    /// Whether this radio can be reached through the CW Bridge.
    /// True for any radio with a CAT serial port, which is everything
    /// except FlexRadios in this catalog.
    public static func isBridgeCompatible(for entry: CatalogEntry) -> Bool {
        guard entry.category == .radio else {
            return false
        }
        let normalized = normalize(entry.manufacturer + " " + entry.name)
        if normalized.contains("flex") {
            return false
        }
        return true
    }

    // MARK: Private

    private static let civKeywords: Set<String> = [
        "icom",
        "xiegu",
    ]

    private static let kenwoodKeywords: Set<String> = [
        "kenwood",
        "elecraft",
        "yaesu",
    ]

    private static func normalize(_ str: String) -> String {
        str.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
    }
}
