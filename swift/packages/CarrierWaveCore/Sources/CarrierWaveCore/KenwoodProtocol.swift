import CarrierWaveCwFfi

// MARK: - KenwoodProtocol

/// Kenwood/Elecraft K3 ASCII text command encoding/decoding.
///
/// Commands are terminated by `;`. Frequencies are 11-digit Hz strings.
/// Example: `FA00014060000;` sets VFO A to 14.060 MHz.
///
/// The command/response wire logic lives in the shared Rust core
/// (`cw_domain::kenwood`); this is a thin facade delegating to the generated FFI.
public enum KenwoodProtocol {
    /// Command terminator
    public static let terminator: Character = ";"

    // MARK: - Command Building

    /// Build a set-frequency command (VFO A).
    /// Format: `FA` + 11-digit Hz + `;`
    public static func setFrequency(hz: UInt64) -> String {
        kenwoodSetFrequency(hz: hz)
    }

    /// Build a read-frequency command (VFO A).
    public static func readFrequency() -> String {
        kenwoodReadFrequency()
    }

    /// Build a set-mode command.
    /// Format: `MD` + mode digit + `;`
    public static func setMode(_ mode: KenwoodMode) -> String {
        kenwoodSetMode(modeRaw: Int32(mode.rawValue))
    }

    /// Build a read-mode command.
    public static func readMode() -> String {
        kenwoodReadMode()
    }

    // MARK: - XIT/RIT Commands

    /// Build a set-XIT command.
    /// Format: `XT` + 0 (off) or 1 (on) + `;`
    public static func setXIT(on: Bool) -> String {
        kenwoodSetXit(on: on)
    }

    /// Build a read-XIT command.
    public static func readXIT() -> String {
        kenwoodReadXit()
    }

    /// Build an absolute RIT/XIT offset command.
    /// Format: `RO` + sign (+/-) + 4-digit Hz value + `;`
    /// Range: -9999 to +9999 Hz.
    public static func setRITXITOffset(hz: Int) -> String {
        kenwoodSetRitXitOffset(hz: Int32(clamping: hz))
    }

    /// Build a read-RIT command.
    public static func readRIT() -> String {
        kenwoodReadRit()
    }

    /// Build a read-RIT/XIT offset command.
    public static func readRITXITOffset() -> String {
        kenwoodReadRitXitOffset()
    }

    /// Build a clear RIT/XIT offset command.
    /// Format: `RC;` — sets offset to zero.
    public static func clearRITXIT() -> String {
        kenwoodClearRitXit()
    }

    // MARK: - Power Level Commands

    /// Build a set-power-level command.
    /// Format: `PC` + 3-digit watts + `;`
    public static func setPowerLevel(watts: UInt8) -> String {
        kenwoodSetPowerLevel(watts: watts)
    }

    /// Build a read-power-level command.
    public static func readPowerLevel() -> String {
        kenwoodReadPowerLevel()
    }

    // MARK: - Response Parsing

    /// Parse a frequency response string into Hz.
    /// Supports both Kenwood 11-digit (`FA00014060000`) and Yaesu 9-digit (`FA014060000`) formats.
    public static func parseFrequencyResponse(_ response: String) -> UInt64? {
        kenwoodParseFrequencyResponse(response: response)
    }

    /// Parse a mode response string (e.g. `MD3`) into a KenwoodMode.
    public static func parseModeResponse(_ response: String) -> KenwoodMode? {
        kenwoodParseModeResponse(response: response).flatMap { KenwoodMode(rawValue: Int($0)) }
    }

    /// Parse an XIT response string (e.g. `XT1`) into on/off.
    public static func parseXITResponse(_ response: String) -> Bool? {
        kenwoodParseXitResponse(response: response)
    }

    /// Parse a RIT response string (e.g. `RT1`) into on/off.
    public static func parseRITResponse(_ response: String) -> Bool? {
        kenwoodParseRitResponse(response: response)
    }

    /// Parse a RIT/XIT offset response (e.g. `RO+0100` or `RO-0050`) into Hz.
    public static func parseRITXITOffsetResponse(_ response: String) -> Int? {
        kenwoodParseRitXitOffsetResponse(response: response).map(Int.init)
    }

    /// Parse a power level response (e.g. `PC005`) into watts.
    public static func parsePowerLevelResponse(_ response: String) -> UInt8? {
        kenwoodParsePowerLevelResponse(response: response)
    }

    /// Extract complete `;`-terminated responses from a text buffer.
    /// Returns parsed response strings (without terminator) and bytes consumed.
    /// Unconsumed characters should be retained for subsequent calls.
    public static func extractResponses(
        from buffer: String
    ) -> (responses: [String], consumed: Int) {
        let result = kenwoodExtractResponses(buffer: buffer)
        return (result.responses, Int(result.consumed))
    }
}

// MARK: - KenwoodMode

/// Kenwood mode digits.
/// K3 command reference: MD + digit.
///
/// The wire digit (`rawValue`) is the enum's identity; the canonical mode-string
/// mappings delegate to the shared Rust core.
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
        kenwoodModeCarrierWaveMode(modeRaw: Int32(rawValue)) ?? ""
    }

    /// Create from a Carrier Wave mode string.
    /// Returns nil for modes without a Kenwood equivalent.
    public static func from(carrierWaveMode: String) -> KenwoodMode? {
        kenwoodModeRawFromCarrierWaveMode(mode: carrierWaveMode).flatMap { KenwoodMode(rawValue: Int($0)) }
    }
}
