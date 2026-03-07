// MARK: - KenwoodProtocol

/// Kenwood/Elecraft K3 ASCII text command encoding/decoding.
///
/// Commands are terminated by `;`. Frequencies are 11-digit Hz strings.
/// Example: `FA00014060000;` sets VFO A to 14.060 MHz.
public enum KenwoodProtocol {
    /// Command terminator
    public static let terminator: Character = ";"

    // MARK: - Command Building

    /// Build a set-frequency command (VFO A).
    /// Format: `FA` + 11-digit Hz + `;`
    public static func setFrequency(hz: UInt64) -> String {
        let digits = String(format: "%011llu", hz)
        return "FA\(digits);"
    }

    /// Build a read-frequency command (VFO A).
    public static func readFrequency() -> String {
        "FA;"
    }

    /// Build a set-mode command.
    /// Format: `MD` + mode digit + `;`
    public static func setMode(_ mode: KenwoodMode) -> String {
        "MD\(mode.rawValue);"
    }

    /// Build a read-mode command.
    public static func readMode() -> String {
        "MD;"
    }

    // MARK: - XIT/RIT Commands

    /// Build a set-XIT command.
    /// Format: `XT` + 0 (off) or 1 (on) + `;`
    public static func setXIT(on: Bool) -> String {
        "XT\(on ? 1 : 0);"
    }

    /// Build a read-XIT command.
    public static func readXIT() -> String {
        "XT;"
    }

    /// Build an absolute RIT/XIT offset command.
    /// Format: `RO` + sign (+/-) + 4-digit Hz value + `;`
    /// Range: -9999 to +9999 Hz.
    public static func setRITXITOffset(hz: Int) -> String {
        let clamped = max(-9_999, min(9_999, hz))
        let sign = clamped >= 0 ? "+" : "-"
        let value = String(format: "%04d", abs(clamped))
        return "RO\(sign)\(value);"
    }

    /// Build a read-RIT command.
    public static func readRIT() -> String {
        "RT;"
    }

    /// Build a read-RIT/XIT offset command.
    public static func readRITXITOffset() -> String {
        "RO;"
    }

    /// Build a clear RIT/XIT offset command.
    /// Format: `RC;` — sets offset to zero.
    public static func clearRITXIT() -> String {
        "RC;"
    }

    // MARK: - Response Parsing

    /// Parse a frequency response string (e.g. `FA00014060000`) into Hz.
    /// Expects the `FA` prefix followed by 11 digits.
    public static func parseFrequencyResponse(_ response: String) -> UInt64? {
        guard response.hasPrefix("FA"), response.count >= 13 else {
            return nil
        }
        let digits = response.dropFirst(2)
        return UInt64(digits)
    }

    /// Parse a mode response string (e.g. `MD3`) into a KenwoodMode.
    public static func parseModeResponse(_ response: String) -> KenwoodMode? {
        guard response.hasPrefix("MD"), response.count >= 3 else {
            return nil
        }
        let digitStr = response.dropFirst(2)
        guard let digit = Int(digitStr) else {
            return nil
        }
        return KenwoodMode(rawValue: digit)
    }

    /// Parse an XIT response string (e.g. `XT1`) into on/off.
    public static func parseXITResponse(_ response: String) -> Bool? {
        guard response.hasPrefix("XT"), response.count >= 3 else {
            return nil
        }
        return response.dropFirst(2) == "1"
    }

    /// Parse a RIT response string (e.g. `RT1`) into on/off.
    public static func parseRITResponse(_ response: String) -> Bool? {
        guard response.hasPrefix("RT"), response.count >= 3 else {
            return nil
        }
        return response.dropFirst(2) == "1"
    }

    /// Parse a RIT/XIT offset response (e.g. `RO+0100` or `RO-0050`) into Hz.
    public static func parseRITXITOffsetResponse(_ response: String) -> Int? {
        guard response.hasPrefix("RO"), response.count >= 7 else {
            return nil
        }
        let offsetStr = response.dropFirst(2)
        return Int(offsetStr)
    }

    /// Extract complete `;`-terminated responses from a text buffer.
    /// Returns parsed response strings (without terminator) and bytes consumed.
    /// Unconsumed characters should be retained for subsequent calls.
    public static func extractResponses(
        from buffer: String
    ) -> (responses: [String], consumed: Int) {
        var responses: [String] = []
        var consumed = 0
        var remaining = buffer[...]

        while let semiIdx = remaining.firstIndex(of: ";") {
            let response = String(remaining[remaining.startIndex ..< semiIdx])
            if !response.isEmpty {
                responses.append(response)
            }
            let afterSemi = remaining.index(after: semiIdx)
            consumed = buffer.distance(from: buffer.startIndex, to: afterSemi)
            remaining = remaining[afterSemi...]
        }

        return (responses, consumed)
    }
}

// MARK: - KenwoodMode

/// Kenwood mode digits.
/// K3 command reference: MD + digit.
public enum KenwoodMode: Int, CaseIterable, Sendable {
    case lsb = 1
    case usb = 2
    case cw = 3
    case fm = 4
    case am = 5
    case data = 6
    case cwR = 7
    case dataR = 9

    // MARK: Public

    /// Map to Carrier Wave mode string.
    public var carrierWaveMode: String {
        switch self {
        case .lsb: "LSB"
        case .usb: "USB"
        case .cw,
             .cwR: "CW"
        case .fm: "FM"
        case .am: "AM"
        case .data,
             .dataR: "DATA"
        }
    }

    /// Create from a Carrier Wave mode string.
    /// Returns nil for modes without a Kenwood equivalent.
    public static func from(carrierWaveMode: String) -> KenwoodMode? {
        switch carrierWaveMode.uppercased() {
        case "LSB": .lsb
        case "USB",
             "SSB": .usb
        case "CW": .cw
        case "FM": .fm
        case "AM": .am
        case "DATA",
             "FT8",
             "FT4",
             "RTTY": .data
        default: nil
        }
    }
}
