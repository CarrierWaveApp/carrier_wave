import CarrierWaveData
import Foundation

// MARK: - RigProtocolDetector

/// Maps free-text rig names to `RigProtocol` using normalized lookup.
nonisolated enum RigProtocolDetector {
    // MARK: Internal

    // MARK: - Bridge ID Detection

    /// Result of bridge radio detection — protocol + human-readable name.
    struct BridgeDetectionResult {
        let rigProtocol: RigProtocol
        let radioName: String
        let frameType: FrameAssembler.FrameType
    }

    /// Detect the protocol for a given rig name.
    /// Returns nil if the rig is unrecognized (caller should use current default).
    static func detect(rigName: String?) -> RigProtocol? {
        guard let rigName, !rigName.isEmpty else {
            return nil
        }
        let normalized = normalize(rigName)

        // Check for manufacturer keywords
        if let match = manufacturerKeywords.first(where: { normalized.contains($0.0) }) {
            return match.1
        }

        // Check for model prefixes
        if let match = modelPrefixes.first(where: { normalized.hasPrefix($0.0) }) {
            return match.1
        }

        return nil
    }

    /// Map a raw bridge ID response to a protocol and radio name.
    ///
    /// - Parameters:
    ///   - rawID: Raw ID string from bridge (e.g. "ID020" for Kenwood, "70" for CI-V).
    ///   - protocolType: Bridge-reported protocol (0x01=Kenwood, 0x02=CI-V).
    /// - Returns: Detection result, or nil if the ID is unrecognized.
    static func detect(
        bridgeID rawID: String,
        protocolType: BridgeFrame.RadioProtocolType
    ) -> BridgeDetectionResult? {
        switch protocolType {
        case .kenwood:
            if let name = kenwoodIDTable[rawID] {
                return BridgeDetectionResult(
                    rigProtocol: .kenwood,
                    radioName: name,
                    frameType: .kenwood
                )
            }
            // Unknown Kenwood ID — still Kenwood protocol
            return BridgeDetectionResult(
                rigProtocol: .kenwood,
                radioName: "Kenwood (\(rawID))",
                frameType: .kenwood
            )

        case .civ:
            if let name = civAddressTable[rawID.uppercased()] {
                return BridgeDetectionResult(
                    rigProtocol: .civ,
                    radioName: name,
                    frameType: .civ
                )
            }
            // Unknown CI-V address — still CI-V protocol
            return BridgeDetectionResult(
                rigProtocol: .civ,
                radioName: "CI-V (0x\(rawID))",
                frameType: .civ
            )
        }
    }

    // MARK: Private

    private static let manufacturerKeywords: [(String, RigProtocol)] = [
        ("icom", .civ),
        ("xiegu", .civ),
        ("elecraft", .kenwood),
        ("kenwood", .kenwood),
        ("yaesu", .kenwood), // Yaesu uses Kenwood-compatible commands
    ]

    /// Model number prefixes (after normalization) that identify protocol.
    private static let modelPrefixes: [(String, RigProtocol)] = [
        // Icom IC- models
        ("ic", .civ),
        // Xiegu models
        ("g90", .civ),
        ("g106", .civ),
        ("x5105", .civ),
        ("x6100", .civ),
        // Elecraft models
        ("k1", .kenwood),
        ("k2", .kenwood),
        ("k3", .kenwood),
        ("k4", .kenwood),
        ("kx2", .kenwood),
        ("kx3", .kenwood),
        ("kh1", .kenwood),
        // Kenwood TS- models
        ("ts", .kenwood),
        // Yaesu FT- models
        ("ft", .kenwood),
    ]

    /// Kenwood ID response → human-readable radio name.
    /// Note: Elecraft radios all return ID017 (K3 compatibility).
    /// Use OM command to distinguish: OM AP----;  (KX2 has 'A' at pos 3)
    private static let kenwoodIDTable: [String: String] = [
        "ID017": "Elecraft K3/KX",
        "ID019": "Kenwood TS-990S",
        "ID029": "Kenwood TS-890S",
        "ID0650": "Yaesu FT-891",
        // Synthetic ID from the bridge firmware's FA-probe fallback (the
        // Quansheng CAT build has no ID command) — mirrors detect.rs.
        "IDQSK5": "Quansheng UV-K5",
    ]

    /// CI-V address (hex string) → human-readable radio name.
    private static let civAddressTable: [String: String] = [
        "70": "Xiegu G90",
        "76": "Xiegu G106",
        "A4": "Icom IC-7300",
        "94": "Icom IC-705",
        "98": "Icom IC-905",
    ]

    private static func normalize(_ string: String) -> String {
        string.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
    }
}
