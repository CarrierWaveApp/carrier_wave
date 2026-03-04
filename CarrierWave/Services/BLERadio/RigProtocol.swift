import CarrierWaveData
import Foundation

// MARK: - RigProtocol

/// Radio command protocol type.
nonisolated enum RigProtocol: String, Codable, CaseIterable, Sendable {
    case civ
    case kenwood

    // MARK: Internal

    var displayName: String {
        switch self {
        case .civ: "CI-V (Icom)"
        case .kenwood: "Kenwood/Elecraft"
        }
    }
}

// MARK: - RigResponse

/// Unified response type from either protocol.
nonisolated enum RigResponse: Sendable {
    case civ(CIVFrame)
    case kenwood(String)
}

// MARK: - RigProtocolHandler

/// Encapsulates encode/decode for both CI-V and Kenwood protocols.
nonisolated struct RigProtocolHandler: Sendable {
    // MARK: Lifecycle

    init(protocol rigProtocol: RigProtocol, civAddress: UInt8 = 0xA4) {
        self.rigProtocol = rigProtocol
        self.civAddress = civAddress
    }

    // MARK: Internal

    let rigProtocol: RigProtocol
    let civAddress: UInt8

    // MARK: - Encoding

    func encodeSetFrequency(mhz: Double) -> [UInt8] {
        switch rigProtocol {
        case .civ:
            let hz = CIVProtocol.mhzToHz(mhz)
            let bcd = CIVProtocol.encodeBCDFrequency(hz)
            return CIVProtocol.buildFrame(
                to: civAddress, command: CIVProtocol.cmdSetFreq, data: bcd
            )
        case .kenwood:
            let hz = UInt64(mhz * 1_000_000.0)
            let cmd = KenwoodProtocol.setFrequency(hz: hz)
            return Array(cmd.utf8)
        }
    }

    func encodeReadFrequency() -> [UInt8] {
        switch rigProtocol {
        case .civ:
            CIVProtocol.buildFrame(
                to: civAddress, command: CIVProtocol.cmdReadFreq
            )
        case .kenwood:
            Array(KenwoodProtocol.readFrequency().utf8)
        }
    }

    func encodeSetMode(_ mode: String) -> [UInt8]? {
        switch rigProtocol {
        case .civ:
            guard let civMode = CIVMode.from(carrierWaveMode: mode) else {
                return nil
            }
            return CIVProtocol.buildFrame(
                to: civAddress, command: CIVProtocol.cmdSetMode,
                data: [civMode.rawValue]
            )
        case .kenwood:
            guard let kMode = KenwoodMode.from(carrierWaveMode: mode) else {
                return nil
            }
            return Array(KenwoodProtocol.setMode(kMode).utf8)
        }
    }

    func encodeReadMode() -> [UInt8] {
        switch rigProtocol {
        case .civ:
            CIVProtocol.buildFrame(
                to: civAddress, command: CIVProtocol.cmdReadMode
            )
        case .kenwood:
            Array(KenwoodProtocol.readMode().utf8)
        }
    }

    // MARK: - Response Extraction

    /// Tag identifying the expected response type for pending requests.
    func expectedTagForSetFrequency() -> String {
        switch rigProtocol {
        case .civ: "ack"
        case .kenwood: "FA"
        }
    }

    func expectedTagForReadFrequency() -> String {
        switch rigProtocol {
        case .civ: "freq"
        case .kenwood: "FA"
        }
    }

    func expectedTagForSetMode() -> String {
        switch rigProtocol {
        case .civ: "ack"
        case .kenwood: "MD"
        }
    }

    func expectedTagForReadMode() -> String {
        switch rigProtocol {
        case .civ: "mode"
        case .kenwood: "MD"
        }
    }

    /// Extract responses from a byte buffer.
    /// Returns parsed responses and the number of bytes consumed.
    func extractResponses(
        from buffer: [UInt8]
    ) -> (responses: [RigResponse], consumed: Int) {
        switch rigProtocol {
        case .civ:
            let (frames, consumed) = CIVProtocol.extractFrames(from: buffer)
            let responses = frames
                .filter { $0.to == CIVProtocol.controllerAddress }
                .map { RigResponse.civ($0) }
            return (responses, consumed)
        case .kenwood:
            let text = String(bytes: buffer, encoding: .ascii) ?? ""
            let (parsed, consumed) = KenwoodProtocol.extractResponses(from: text)
            let responses = parsed.map { RigResponse.kenwood($0) }
            return (responses, consumed)
        }
    }

    // MARK: - Response Decoding

    /// Decode a frequency (MHz) from a response.
    func decodeFrequency(_ response: RigResponse) -> Double? {
        switch response {
        case let .civ(frame):
            guard let hz = CIVProtocol.parseBCDFrequency(frame.data) else {
                return nil
            }
            return CIVProtocol.hzToMHz(hz)
        case let .kenwood(text):
            guard let hz = KenwoodProtocol.parseFrequencyResponse(text) else {
                return nil
            }
            return Double(hz) / 1_000_000.0
        }
    }

    /// Decode a mode string from a response.
    func decodeMode(_ response: RigResponse) -> String? {
        switch response {
        case let .civ(frame):
            guard let modeByte = frame.data.first,
                  let civMode = CIVMode(rawValue: modeByte)
            else {
                return nil
            }
            return civMode.carrierWaveMode
        case let .kenwood(text):
            guard let mode = KenwoodProtocol.parseModeResponse(text) else {
                return nil
            }
            return mode.carrierWaveMode
        }
    }

    /// Check if a response is an ACK.
    func isAck(_ response: RigResponse) -> Bool {
        switch response {
        case let .civ(frame): frame.isAck
        case .kenwood: true // Kenwood echoes the command as ACK
        }
    }

    /// Check if a response is a NAK.
    func isNak(_ response: RigResponse) -> Bool {
        switch response {
        case let .civ(frame): frame.isNak
        case let .kenwood(text): text == "?;" || text == "?"
        }
    }

    /// Check if a response matches the expected tag.
    func responseMatchesTag(
        _ response: RigResponse,
        expectedTag: String
    ) -> Bool {
        switch response {
        case let .civ(frame):
            switch expectedTag {
            case "ack": frame.isAck || frame.isNak
            case "freq": frame.command == CIVProtocol.cmdReadFreq
            case "mode": frame.command == CIVProtocol.cmdReadMode
            default: false
            }
        case let .kenwood(text):
            // Kenwood: match on command prefix (FA, MD) or NAK (?)
            text.hasPrefix(expectedTag) || text == "?" || text == "?;"
        }
    }
}

// MARK: - RigProtocolDetector

/// Maps free-text rig names to `RigProtocol` using normalized lookup.
nonisolated enum RigProtocolDetector {
    // MARK: Internal

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

    private static func normalize(_ string: String) -> String {
        string.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
    }
}
