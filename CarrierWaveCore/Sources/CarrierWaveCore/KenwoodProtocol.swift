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
