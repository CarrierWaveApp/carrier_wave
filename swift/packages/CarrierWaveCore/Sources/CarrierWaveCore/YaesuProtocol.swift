import CarrierWaveCwFfi

// MARK: - YaesuProtocol

/// Yaesu CAT ASCII text command encoding/decoding.
///
/// Commands are terminated by `;`. Frequencies are 9-digit Hz strings.
/// Example: `FA014250000;` sets VFO A to 14.250 MHz.
///
/// Based on FTDX10 CAT Operation Reference Manual (2308-F).
/// Compatible with FTDX10, FT-991A, FT-710, FTDX101D and other modern Yaesu radios.
///
/// The command/response wire logic lives in the shared Rust core
/// (`cw_domain::yaesu`); this is a thin facade delegating to the generated FFI.
public enum YaesuProtocol {
    /// Command terminator
    public static let terminator: Character = ";"

    // MARK: - Command Building

    /// Build a set-frequency command (VFO A).
    /// Format: `FA` + 9-digit Hz + `;`
    public static func setFrequency(hz: UInt64) -> String {
        yaesuSetFrequency(hz: hz)
    }

    /// Build a read-frequency command (VFO A).
    public static func readFrequency() -> String {
        yaesuReadFrequency()
    }

    /// Build a set-mode command (main band).
    /// Format: `MD` + P1 (band) + P2 (mode hex char) + `;`
    public static func setMode(_ mode: YaesuMode, band: Int = 0) -> String {
        yaesuSetMode(protocolChar: String(mode.protocolChar), band: Int32(band))
    }

    /// Build a read-mode command (main band).
    public static func readMode(band: Int = 0) -> String {
        yaesuReadMode(band: Int32(band))
    }

    /// Build a read-information command.
    /// Returns comprehensive status: freq, mode, clarifier, etc.
    public static func readInformation() -> String {
        yaesuReadInformation()
    }

    /// Build a PTT set command.
    /// P1: 0=RADIO TX OFF/CAT TX OFF, 1=RADIO TX OFF/CAT TX ON
    public static func setPTT(on: Bool) -> String {
        yaesuSetPtt(on: on)
    }

    /// Build a PTT read command.
    public static func readPTT() -> String {
        yaesuReadPtt()
    }

    // MARK: - Clarifier (RIT/XIT) Commands

    /// Build a set-RIT (RX Clarifier) command.
    /// P1: 0=OFF, 1=ON
    public static func setRIT(on: Bool) -> String {
        yaesuSetRit(on: on)
    }

    /// Build a read-RIT command.
    public static func readRIT() -> String {
        yaesuReadRit()
    }

    /// Build a set-XIT (TX Clarifier) command.
    /// P1: 0=OFF, 1=ON
    public static func setXIT(on: Bool) -> String {
        yaesuSetXit(on: on)
    }

    /// Build a read-XIT command.
    public static func readXIT() -> String {
        yaesuReadXit()
    }

    /// Build a clarifier clear command (sets offset to zero).
    public static func clearClarifier() -> String {
        yaesuClearClarifier()
    }

    /// Build a clarifier-up command (increase offset).
    /// P1: 0000-9990 Hz (in 10 Hz steps)
    public static func clarifierUp(hz: Int) -> String {
        yaesuClarifierUp(hz: Int32(clamping: hz))
    }

    /// Build a clarifier-down command (decrease offset).
    /// P1: 0000-9990 Hz
    public static func clarifierDown(hz: Int) -> String {
        yaesuClarifierDown(hz: Int32(clamping: hz))
    }

    // MARK: - CW Commands

    /// Build keyer memory write + playback commands for CW text sending.
    /// Uses keyer memory channel 5 to avoid overwriting user channels 1-4.
    /// Format: `KM5<text>;KY5;`
    public static func sendCW(_ text: String) -> String {
        yaesuSendCw(text: text)
    }

    // MARK: - Response Parsing

    /// Parse a frequency response (e.g. `FA014250000`) into Hz.
    /// Expects `FA` prefix followed by 9 digits.
    public static func parseFrequencyResponse(_ response: String) -> UInt64? {
        yaesuParseFrequencyResponse(response: response)
    }

    /// Parse a mode response (e.g. `MD0C`) into a YaesuMode.
    /// Format: `MD` + P1 (band) + P2 (mode char)
    public static func parseModeResponse(_ response: String) -> YaesuMode? {
        yaesuParseModeResponse(response: response).flatMap { char in
            char.first.flatMap { YaesuMode(protocolChar: $0) }
        }
    }

    /// Parse a TX response (e.g. `TX0` or `TX2`) into transmit state.
    /// 0=RX, 1=CAT TX ON, 2=RADIO TX ON
    public static func parseTXResponse(_ response: String) -> Bool? {
        yaesuParseTxResponse(response: response)
    }

    /// Parse an RT (RIT/RX Clarifier) response into on/off.
    public static func parseRITResponse(_ response: String) -> Bool? {
        yaesuParseRitResponse(response: response)
    }

    /// Parse an XT (XIT/TX Clarifier) response into on/off.
    public static func parseXITResponse(_ response: String) -> Bool? {
        yaesuParseXitResponse(response: response)
    }

    /// Parse an IF (Information) response into structured data.
    /// Format: `IF` + P1(3) + P2(9) + P3(5) + P4(1) + P5(1) + P6(1) + P7(1) + P8(1) + P9(2) + P10(1) + `;`
    public static func parseInformationResponse(_ response: String) -> YaesuInformation? {
        yaesuParseInformationResponse(response: response).map { ffi in
            YaesuInformation(
                frequencyHz: ffi.frequencyHz,
                clarifierOffset: Int(ffi.clarifierOffset),
                rxClarifier: ffi.rxClarifier,
                txClarifier: ffi.txClarifier,
                mode: ffi.mode.flatMap { char in char.first.flatMap { YaesuMode(protocolChar: $0) } }
            )
        }
    }

    /// Extract complete `;`-terminated responses from a text buffer.
    /// Shares the same framing as Kenwood protocol.
    public static func extractResponses(
        from buffer: String
    ) -> (responses: [String], consumed: Int) {
        let result = yaesuExtractResponses(buffer: buffer)
        return (result.responses, Int(result.consumed))
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
///
/// The wire char (`protocolChar`) is the enum's identity; the canonical
/// mode-string mappings delegate to the shared Rust core.
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
        yaesuModeCarrierWaveMode(protocolChar: String(protocolChar)) ?? ""
    }

    /// Create from a Carrier Wave mode string.
    /// Returns nil for modes without a Yaesu equivalent.
    public static func from(carrierWaveMode: String) -> YaesuMode? {
        yaesuModeCharFromCarrierWaveMode(mode: carrierWaveMode).flatMap { char in
            char.first.flatMap { YaesuMode(protocolChar: $0) }
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
