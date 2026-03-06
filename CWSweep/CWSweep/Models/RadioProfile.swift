import Foundation

// MARK: - RadioProtocolType

/// Supported radio CAT protocol families
enum RadioProtocolType: String, Codable, CaseIterable {
    case civ // Icom CI-V
    case kenwood // Kenwood TS-xxx
    case elecraft // Elecraft (Kenwood extended)
    case yaesu // Yaesu CAT (future)
    case flex // FlexRadio SmartSDR (future)
}

// MARK: - RadioModel

/// Known radio models with pre-configured defaults
struct RadioModel: Codable, Identifiable, Hashable {
    static let knownModels: [RadioModel] = [
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

    /// Create from a known radio model
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
