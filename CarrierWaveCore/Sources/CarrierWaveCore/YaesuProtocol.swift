import Foundation

// MARK: - YaesuProtocol

/// Yaesu CAT ASCII text command encoding/decoding.
///
/// Commands are terminated by `;`. Frequencies are 9-digit Hz strings.
/// Example: `FA014250000;` sets VFO A to 14.250 MHz.
///
/// Based on FTDX10 CAT Operation Reference Manual (2308-F).
/// Compatible with FTDX10, FT-991A, FT-710, FTDX101D and other modern Yaesu radios.
public enum YaesuProtocol {
    /// Command terminator
    public static let terminator: Character = ";"

    // MARK: - Command Building

    /// Build a set-frequency command (VFO A).
    /// Format: `FA` + 9-digit Hz + `;`
    public static func setFrequency(hz: UInt64) -> String {
        let digits = String(format: "%09llu", hz)
        return "FA\(digits);"
    }

    /// Build a read-frequency command (VFO A).
    public static func readFrequency() -> String {
        "FA;"
    }

    /// Build a set-mode command (main band).
    /// Format: `MD` + P1 (band) + P2 (mode hex char) + `;`
    public static func setMode(_ mode: YaesuMode, band: Int = 0) -> String {
        "MD\(band)\(mode.protocolChar);"
    }

    /// Build a read-mode command (main band).
    public static func readMode(band: Int = 0) -> String {
        "MD\(band);"
    }

    /// Build a read-information command.
    /// Returns comprehensive status: freq, mode, clarifier, etc.
    public static func readInformation() -> String {
        "IF;"
    }

    /// Build a PTT set command.
    /// P1: 0=RADIO TX OFF/CAT TX OFF, 1=RADIO TX OFF/CAT TX ON
    public static func setPTT(on: Bool) -> String {
        "TX\(on ? 1 : 0);"
    }

    /// Build a PTT read command.
    public static func readPTT() -> String {
        "TX;"
    }

    // MARK: - Clarifier (RIT/XIT) Commands

    /// Build a set-RIT (RX Clarifier) command.
    /// P1: 0=OFF, 1=ON
    public static func setRIT(on: Bool) -> String {
        "RT\(on ? 1 : 0);"
    }

    /// Build a read-RIT command.
    public static func readRIT() -> String {
        "RT;"
    }

    /// Build a set-XIT (TX Clarifier) command.
    /// P1: 0=OFF, 1=ON
    public static func setXIT(on: Bool) -> String {
        "XT\(on ? 1 : 0);"
    }

    /// Build a read-XIT command.
    public static func readXIT() -> String {
        "XT;"
    }

    /// Build a clarifier clear command (sets offset to zero).
    public static func clearClarifier() -> String {
        "RC;"
    }

    /// Build a clarifier-up command (increase offset).
    /// P1: 0000-9990 Hz (in 10 Hz steps)
    public static func clarifierUp(hz: Int) -> String {
        let clamped = max(0, min(9_990, hz))
        return String(format: "RU%04d;", clamped)
    }

    /// Build a clarifier-down command (decrease offset).
    /// P1: 0000-9990 Hz
    public static func clarifierDown(hz: Int) -> String {
        let clamped = max(0, min(9_990, hz))
        return String(format: "RD%04d;", clamped)
    }

    // MARK: - CW Commands

    /// Build keyer memory write + playback commands for CW text sending.
    /// Uses keyer memory channel 5 to avoid overwriting user channels 1-4.
    /// Format: `KM5<text>;KY5;`
    public static func sendCW(_ text: String) -> String {
        let truncated = String(text.prefix(50))
        return "KM5\(truncated);KY5;"
    }

    // MARK: - Response Parsing

    /// Parse a frequency response (e.g. `FA014250000`) into Hz.
    /// Expects `FA` prefix followed by 9 digits.
    public static func parseFrequencyResponse(_ response: String) -> UInt64? {
        guard response.hasPrefix("FA"), response.count >= 11 else {
            return nil
        }
        let digits = response.dropFirst(2)
        return UInt64(digits)
    }

    /// Parse a mode response (e.g. `MD0C`) into a YaesuMode.
    /// Format: `MD` + P1 (band) + P2 (mode char)
    public static func parseModeResponse(_ response: String) -> YaesuMode? {
        guard response.hasPrefix("MD"), response.count >= 4 else {
            return nil
        }
        let modeChar = response[response.index(response.startIndex, offsetBy: 3)]
        return YaesuMode(protocolChar: modeChar)
    }

    /// Parse a TX response (e.g. `TX0` or `TX2`) into transmit state.
    /// 0=RX, 1=CAT TX ON, 2=RADIO TX ON
    public static func parseTXResponse(_ response: String) -> Bool? {
        guard response.hasPrefix("TX"), response.count >= 3 else {
            return nil
        }
        let stateChar = response[response.index(response.startIndex, offsetBy: 2)]
        return stateChar != "0"
    }

    /// Parse an RT (RIT/RX Clarifier) response into on/off.
    public static func parseRITResponse(_ response: String) -> Bool? {
        guard response.hasPrefix("RT"), response.count >= 3 else {
            return nil
        }
        return response.dropFirst(2) == "1"
    }

    /// Parse an XT (XIT/TX Clarifier) response into on/off.
    public static func parseXITResponse(_ response: String) -> Bool? {
        guard response.hasPrefix("XT"), response.count >= 3 else {
            return nil
        }
        return response.dropFirst(2) == "1"
    }

    /// Parse an IF (Information) response into structured data.
    /// Format: `IF` + P1(3) + P2(9) + P3(5) + P4(1) + P5(1) + P6(1) + P7(1) + P8(1) + P9(2) + P10(1) + `;`
    public static func parseInformationResponse(_ response: String) -> YaesuInformation? {
        // Minimum: IF + 25 chars = 27 (without terminator)
        guard response.hasPrefix("IF"), response.count >= 27 else {
            return nil
        }

        let chars = Array(response)
        // P2: frequency in Hz (positions 5-13, indices 5..13 in 0-indexed, but chars[5]..chars[13])
        // Actually: IF is chars[0..1], P1 is chars[2..4], P2 is chars[5..13]
        let freqStr = String(chars[5 ... 13])
        guard let freqHz = UInt64(freqStr) else {
            return nil
        }

        // P3: clarifier direction + offset (chars[14..18])
        let clarStr = String(chars[14 ... 18])
        let clarOffset = Int(clarStr) ?? 0

        // P4: RX CLAR (char[19])
        let rxClar = chars[19] == Character("1")

        // P5: TX CLAR (char[20])
        let txClar = chars[20] == Character("1")

        // P6: Mode (char[21])
        let mode = YaesuMode(protocolChar: chars[21])

        return YaesuInformation(
            frequencyHz: freqHz,
            clarifierOffset: clarOffset,
            rxClarifier: rxClar,
            txClarifier: txClar,
            mode: mode
        )
    }

    /// Extract complete `;`-terminated responses from a text buffer.
    /// Shares the same framing as Kenwood protocol.
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

// MARK: - YaesuInformation

/// Parsed IF (Information) response from a Yaesu radio.
public struct YaesuInformation: Equatable, Sendable {
    public let frequencyHz: UInt64
    public let clarifierOffset: Int
    public let rxClarifier: Bool
    public let txClarifier: Bool
    public let mode: YaesuMode?
}

// MARK: - YaesuMode

/// Yaesu operating mode characters.
/// Mode is encoded as a single hex character in CAT commands.
public enum YaesuMode: CaseIterable, Sendable {
    case lsb
    case usb
    case cwU
    case fm
    case am
    case rttyL
    case cwL
    case dataL
    case rttyU
    case dataFM
    case fmN
    case dataU
    case amN
    case psk
    case dataFMN

    // MARK: Lifecycle

    /// Create from a protocol character received from the radio.
    public init?(protocolChar: Character) {
        guard let mode = Self.charToMode[protocolChar] else {
            return nil
        }
        self = mode
    }

    // MARK: Public

    /// All cases for CaseIterable
    public static var allCases: [YaesuMode] {
        [.lsb, .usb, .cwU, .fm, .am, .rttyL, .cwL, .dataL,
         .rttyU, .dataFM, .fmN, .dataU, .amN, .psk, .dataFMN]
    }

    /// Protocol character sent/received in CAT commands.
    public var protocolChar: Character {
        switch self {
        case .lsb: "1"
        case .usb: "2"
        case .cwU: "3"
        case .fm: "4"
        case .am: "5"
        case .rttyL: "6"
        case .cwL: "7"
        case .dataL: "8"
        case .rttyU: "9"
        case .dataFM: "A"
        case .fmN: "B"
        case .dataU: "C"
        case .amN: "D"
        case .psk: "E"
        case .dataFMN: "F"
        }
    }

    /// Map to Carrier Wave mode string.
    public var carrierWaveMode: String {
        switch self {
        case .lsb: "LSB"
        case .usb: "USB"
        case .cwU,
             .cwL: "CW"
        case .fm,
             .fmN: "FM"
        case .am,
             .amN: "AM"
        case .rttyL,
             .rttyU: "RTTY"
        case .dataL,
             .dataU,
             .dataFM,
             .dataFMN: "DATA"
        case .psk: "DATA"
        }
    }

    /// Create from a Carrier Wave mode string.
    /// Returns nil for modes without a Yaesu equivalent.
    public static func from(carrierWaveMode: String) -> YaesuMode? {
        switch carrierWaveMode.uppercased() {
        case "LSB": .lsb
        case "USB",
             "SSB": .usb
        case "CW": .cwU
        case "FM": .fm
        case "AM": .am
        case "RTTY": .rttyL
        case "DATA",
             "FT8",
             "FT4": .dataU
        default: nil
        }
    }

    // MARK: Private

    /// Lookup table from protocol character to mode.
    private static let charToMode: [Character: YaesuMode] = [
        "1": .lsb, "2": .usb, "3": .cwU, "4": .fm, "5": .am,
        "6": .rttyL, "7": .cwL, "8": .dataL, "9": .rttyU,
        "A": .dataFM, "B": .fmN, "C": .dataU, "D": .amN,
        "E": .psk, "F": .dataFMN,
    ]
}
