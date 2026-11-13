import Foundation

// MARK: - BridgeRigDetector

/// Maps raw CW Bridge radio-ID responses into a CW Sweep `RadioProtocolType`
/// and a human-readable radio name.
nonisolated enum BridgeRigDetector {
    // MARK: Internal

    /// Detection result used to configure a `RadioSession` after the bridge
    /// auto-detects a connected radio.
    struct Result {
        let protocolType: RadioProtocolType
        let radioName: String
        let civAddress: UInt8?
    }

    /// Map a raw bridge ID response to a CW Sweep protocol and radio name.
    static func detect(
        rawID: String,
        protocolType: BridgeFrame.BridgeRadioProtocolType
    ) -> Result {
        switch protocolType {
        case .kenwood:
            if let name = kenwoodIDTable[rawID] {
                return Result(
                    protocolType: protocolFor(kenwoodID: rawID),
                    radioName: name,
                    civAddress: nil
                )
            }
            return Result(
                protocolType: .kenwood,
                radioName: "Kenwood (\(rawID))",
                civAddress: nil
            )

        case .civ:
            let key = rawID.uppercased()
            if let entry = civAddressTable[key] {
                return Result(
                    protocolType: .civ,
                    radioName: entry.name,
                    civAddress: entry.address
                )
            }
            let address = UInt8(key, radix: 16)
            return Result(
                protocolType: .civ,
                radioName: "CI-V (0x\(key))",
                civAddress: address
            )
        }
    }

    // MARK: Private

    private static let kenwoodIDTable: [String: String] = [
        "ID017": "Elecraft K3/KX",
        "ID019": "Kenwood TS-990S",
        "ID029": "Kenwood TS-890S",
    ]

    private static let civAddressTable: [String: (name: String, address: UInt8)] = [
        "70": (name: "Xiegu G90", address: 0x70),
        "76": (name: "Xiegu G106", address: 0x76),
        "94": (name: "Icom IC-7300", address: 0x94),
        "A4": (name: "Icom IC-705", address: 0xA4),
        "98": (name: "Icom IC-7610", address: 0x98),
        "A2": (name: "Icom IC-9700", address: 0xA2),
    ]

    /// Elecraft radios return ID017 (K3 compatibility). Treat as Elecraft so
    /// the ElecraftProtocolHandler can drive CW keying extensions.
    private static func protocolFor(kenwoodID: String) -> RadioProtocolType {
        kenwoodID == "ID017" ? .elecraft : .kenwood
    }
}
