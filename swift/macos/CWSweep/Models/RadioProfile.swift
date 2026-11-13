import Foundation

// MARK: - RadioProtocolType

/// Supported radio CAT protocol families
enum RadioProtocolType: String, Codable, CaseIterable {
    case civ // Icom CI-V
    case kenwood // Kenwood TS-xxx
    case elecraft // Elecraft (Kenwood extended)
    case yaesu // Yaesu CAT (FTDX10, FT-991A, FT-710, FTDX101D)
    case flex // FlexRadio SmartSDR (TCP/IP)
    case scuLan10 // Yaesu SCU-LAN10 (UDP/IP)
    case icomWiFi // Icom RS-BA1 WiFi (UDP/IP)
    case cwBridge // CW Bridge (BLE NUS + CWBP framing)

    // MARK: Internal

    /// Whether this protocol uses network (TCP/IP or UDP/IP) instead of serial
    var isNetworkBased: Bool {
        self == .flex || self == .scuLan10 || self == .icomWiFi
    }

    /// Whether this protocol is an SCU-LAN10 connection
    var isSCULAN10: Bool {
        self == .scuLan10
    }

    /// Whether this protocol runs over the CW Bridge (BLE).
    var isCWBridge: Bool {
        self == .cwBridge
    }
}

// MARK: - RadioModel

/// Known radio models with pre-configured defaults
struct RadioModel: Codable, Identifiable, Hashable {
    static let knownModels: [RadioModel] = [
        // FlexRadio — TCP/IP network connection (baud rate unused)
        RadioModel(id: "flex6400", name: "FLEX-6400", manufacturer: "FlexRadio",
                   protocolType: .flex, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),
        RadioModel(id: "flex6400m", name: "FLEX-6400M", manufacturer: "FlexRadio",
                   protocolType: .flex, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),
        RadioModel(id: "flex6600", name: "FLEX-6600", manufacturer: "FlexRadio",
                   protocolType: .flex, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),
        RadioModel(id: "flex6600m", name: "FLEX-6600M", manufacturer: "FlexRadio",
                   protocolType: .flex, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),
        RadioModel(id: "flex6700", name: "FLEX-6700", manufacturer: "FlexRadio",
                   protocolType: .flex, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),

        // Icom CI-V — USB adapters need DTR/RTS for RS-232 transceiver power
        RadioModel(id: "ic7300", name: "IC-7300", manufacturer: "Icom",
                   protocolType: .civ, defaultBaudRate: 19_200, civAddress: 0x94,
                   dtrDefault: true, rtsDefault: true),
        RadioModel(id: "ic7610", name: "IC-7610", manufacturer: "Icom",
                   protocolType: .civ, defaultBaudRate: 19_200, civAddress: 0x98,
                   dtrDefault: true, rtsDefault: true),
        RadioModel(id: "ic705", name: "IC-705", manufacturer: "Icom",
                   protocolType: .civ, defaultBaudRate: 19_200, civAddress: 0xA4,
                   dtrDefault: true, rtsDefault: true),
        // IC-9700 USB CI-V port: scope streaming needs 115200 + "Unlink from [REMOTE]"
        RadioModel(id: "ic9700", name: "IC-9700", manufacturer: "Icom",
                   protocolType: .civ, defaultBaudRate: 115_200, civAddress: 0xA2,
                   dtrDefault: true, rtsDefault: true),
        RadioModel(id: "x6100", name: "X6100", manufacturer: "Xiegu",
                   protocolType: .civ, defaultBaudRate: 19_200, civAddress: 0x70,
                   dtrDefault: true, rtsDefault: true),
        RadioModel(id: "g90", name: "G90", manufacturer: "Xiegu",
                   protocolType: .civ, defaultBaudRate: 19_200, civAddress: 0x70,
                   dtrDefault: true, rtsDefault: true),

        // Kenwood — USB adapters need DTR/RTS for RS-232 transceiver power
        RadioModel(id: "ts890s", name: "TS-890S", manufacturer: "Kenwood",
                   protocolType: .kenwood, defaultBaudRate: 115_200, civAddress: nil,
                   dtrDefault: true, rtsDefault: true),
        RadioModel(id: "ts590sg", name: "TS-590SG", manufacturer: "Kenwood",
                   protocolType: .kenwood, defaultBaudRate: 9_600, civAddress: nil,
                   dtrDefault: true, rtsDefault: true),

        // Elecraft — DTR/RTS triggers TEST mode per K3 manual
        RadioModel(id: "k3", name: "K3/K3S", manufacturer: "Elecraft",
                   protocolType: .elecraft, defaultBaudRate: 38_400, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),
        RadioModel(id: "k4", name: "K4", manufacturer: "Elecraft",
                   protocolType: .elecraft, defaultBaudRate: 115_200, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),

        // Yaesu — USB virtual COM port (built-in UART bridge)
        RadioModel(id: "ftdx10", name: "FTDX10", manufacturer: "Yaesu",
                   protocolType: .yaesu, defaultBaudRate: 38_400, civAddress: nil,
                   dtrDefault: true, rtsDefault: true),
        RadioModel(id: "ft991a", name: "FT-991A", manufacturer: "Yaesu",
                   protocolType: .yaesu, defaultBaudRate: 38_400, civAddress: nil,
                   dtrDefault: true, rtsDefault: true),
        RadioModel(id: "ft710", name: "FT-710", manufacturer: "Yaesu",
                   protocolType: .yaesu, defaultBaudRate: 38_400, civAddress: nil,
                   dtrDefault: true, rtsDefault: true),
        RadioModel(id: "ftdx101d", name: "FTDX101D", manufacturer: "Yaesu",
                   protocolType: .yaesu, defaultBaudRate: 38_400, civAddress: nil,
                   dtrDefault: true, rtsDefault: true),

        // Yaesu SCU-LAN10 — UDP network connection with scope/waterfall
        RadioModel(id: "sculan10-ftdx101mp", name: "FTDX101MP (SCU-LAN10)", manufacturer: "Yaesu",
                   protocolType: .scuLan10, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),
        RadioModel(id: "sculan10-ftdx101d", name: "FTDX101D (SCU-LAN10)", manufacturer: "Yaesu",
                   protocolType: .scuLan10, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),
        RadioModel(id: "sculan10-ftdx10", name: "FTDX10 (SCU-LAN10)", manufacturer: "Yaesu",
                   protocolType: .scuLan10, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),
        RadioModel(id: "sculan10-ft710", name: "FT-710 (SCU-LAN10)", manufacturer: "Yaesu",
                   protocolType: .scuLan10, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),

        // Icom WiFi — RS-BA1 UDP protocol
        RadioModel(id: "ic705-wifi", name: "IC-705 (WiFi)", manufacturer: "Icom",
                   protocolType: .icomWiFi, defaultBaudRate: 0, civAddress: 0xA4,
                   dtrDefault: false, rtsDefault: false),
        RadioModel(id: "ic7610-wifi", name: "IC-7610 (WiFi)", manufacturer: "Icom",
                   protocolType: .icomWiFi, defaultBaudRate: 0, civAddress: 0x98,
                   dtrDefault: false, rtsDefault: false),
        // IC-9700 wired Ethernet speaks the same RS-BA1 UDP protocol
        RadioModel(id: "ic9700-lan", name: "IC-9700 (LAN)", manufacturer: "Icom",
                   protocolType: .icomWiFi, defaultBaudRate: 0, civAddress: 0xA2,
                   dtrDefault: false, rtsDefault: false),

        // CW Bridge — BLE NUS transport with auto-detected radio
        RadioModel(id: "cwbridge", name: "CW Bridge", manufacturer: "Carrier Wave",
                   protocolType: .cwBridge, defaultBaudRate: 0, civAddress: nil,
                   dtrDefault: false, rtsDefault: false),
    ]

    let id: String
    let name: String
    let manufacturer: String
    let protocolType: RadioProtocolType
    let defaultBaudRate: Int
    let civAddress: UInt8? // Icom CI-V address (nil for non-Icom)
    let dtrDefault: Bool // Assert DTR on open (false for Elecraft — triggers TEST mode)
    let rtsDefault: Bool // Assert RTS on open (false for Elecraft — triggers TEST mode)
}

// MARK: - RadioProfile

/// User configuration for a specific radio connection
struct RadioProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var modelId: String?
    var protocolType: RadioProtocolType
    var serialPortPath: String // e.g., "/dev/cu.usbserial-1234"
    var baudRate: Int
    var civAddress: UInt8?
    var dataBits: Int = 8
    var stopBits: Int = 1
    var parity: ParityType = .none
    var flowControl: FlowControlType = .none
    var dtrSignal: Bool = false
    var rtsSignal: Bool = false

    // MARK: - Network (FlexRadio)

    /// Host IP address for network-connected radios (FlexRadio)
    var networkHost: String?
    /// TCP port for network-connected radios (default 4992)
    var networkPort: UInt16 = 4_992
    /// Slice index to control on FlexRadio (default 0)
    var flexSliceIndex: Int = 0

    // MARK: - SCU-LAN10

    /// SCU-LAN10 username
    var sculan10Username: String?
    /// SCU-LAN10 password
    var sculan10Password: String?

    // MARK: - Icom WiFi

    /// Icom WiFi (RS-BA1) username
    var icomWiFiUsername: String?
    /// Icom WiFi (RS-BA1) password
    var icomWiFiPassword: String?

    // MARK: - CW Bridge (BLE)

    /// BLE peripheral UUID of the selected CW Bridge device.
    var bridgeDeviceUUID: UUID?
    /// Display name of the selected CW Bridge device (for UI).
    var bridgeDeviceName: String?

    /// Whether this profile uses network instead of serial
    var isNetworkRadio: Bool {
        protocolType.isNetworkBased
    }

    /// Create from a known radio model with serial port
    static func from(model: RadioModel, portPath: String) -> RadioProfile {
        RadioProfile(
            name: "\(model.manufacturer) \(model.name)",
            modelId: model.id,
            protocolType: model.protocolType,
            serialPortPath: portPath,
            baudRate: model.defaultBaudRate,
            civAddress: model.civAddress,
            dtrSignal: model.dtrDefault,
            rtsSignal: model.rtsDefault
        )
    }

    /// Create from SCU-LAN10 connection settings
    static func fromSCULAN10(
        model: RadioModel,
        host: String,
        port: UInt16 = 50_000,
        username: String,
        password: String
    ) -> RadioProfile {
        RadioProfile(
            name: "\(model.manufacturer) \(model.name)",
            modelId: model.id,
            protocolType: .scuLan10,
            serialPortPath: "",
            baudRate: 0,
            networkHost: host,
            networkPort: port,
            sculan10Username: username,
            sculan10Password: password
        )
    }

    /// Create from Icom WiFi (RS-BA1) connection settings
    static func fromIcomWiFi(
        model: RadioModel,
        host: String,
        username: String,
        password: String
    ) -> RadioProfile {
        RadioProfile(
            name: "\(model.manufacturer) \(model.name)",
            modelId: model.id,
            protocolType: .icomWiFi,
            serialPortPath: "",
            baudRate: 0,
            civAddress: model.civAddress,
            networkHost: host,
            // RS-BA1 control port. The transport always uses 50001; this keeps
            // the "Connected to … on host:port" log line from showing the Flex
            // default (4992).
            networkPort: 50_001,
            icomWiFiUsername: username,
            icomWiFiPassword: password
        )
    }

    /// Create a CW Bridge profile for a discovered BLE peripheral.
    static func fromBridge(
        deviceUUID: UUID,
        deviceName: String
    ) -> RadioProfile {
        RadioProfile(
            name: deviceName,
            modelId: "cwbridge",
            protocolType: .cwBridge,
            serialPortPath: "",
            baudRate: 0,
            bridgeDeviceUUID: deviceUUID,
            bridgeDeviceName: deviceName
        )
    }

    /// Create from a discovered FlexRadio
    static func fromFlex(
        model: RadioModel,
        host: String,
        port: UInt16 = 4_992,
        radioName: String? = nil
    ) -> RadioProfile {
        RadioProfile(
            name: radioName ?? "\(model.manufacturer) \(model.name)",
            modelId: model.id,
            protocolType: .flex,
            serialPortPath: "", // unused for network
            baudRate: 0,
            networkHost: host,
            networkPort: port
        )
    }
}

// MARK: - ParityType

enum ParityType: String, Codable, CaseIterable {
    case none
    case even
    case odd
}

// MARK: - FlowControlType

enum FlowControlType: String, Codable, CaseIterable {
    case none
    case hardware // RTS/CTS
    case software // XON/XOFF
}
