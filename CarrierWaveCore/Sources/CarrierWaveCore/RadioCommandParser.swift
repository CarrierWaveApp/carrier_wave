//
//  RadioCommandParser.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - RadioCommand

/// Parsed result of a radio command palette input
public struct RadioCommand: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        frequencyMHz: Double? = nil,
        mode: String? = nil,
        splitDirective: SplitDirective? = nil,
        namedCommand: NamedCommand? = nil
    ) {
        self.frequencyMHz = frequencyMHz
        self.mode = mode
        self.splitDirective = splitDirective
        self.namedCommand = namedCommand
    }

    // MARK: Public

    public var frequencyMHz: Double?
    public var mode: String?
    public var splitDirective: SplitDirective?
    public var namedCommand: NamedCommand?

    public var isEmpty: Bool {
        frequencyMHz == nil && mode == nil && splitDirective == nil && namedCommand == nil
    }
}

// MARK: - NamedCommand

/// Named commands beyond radio tuning
public enum NamedCommand: Sendable, Equatable {
    /// Callsign lookup via QRZ/HamDB
    case lookup(callsign: String)
    /// Spot a callsign to the DX cluster
    case spot(callsign: String, frequencyKHz: Double?)
    /// Set POTA park reference on active session
    case setPark(reference: String)
    /// Set SOTA summit reference on active session
    case setSummit(reference: String)
    /// Set TX power
    case setPower(watts: Int)
    /// Send CQ macro (F1)
    case sendCQ
    /// Set CW speed in WPM
    case setSpeed(wpm: Int)
    /// Toggle RUN/S&P operating mode
    case setContestMode(mode: ContestModeValue)
    /// Search log for a callsign
    case findCall(callsign: String)
    /// Show recent N QSOs
    case lastQSOs(count: Int)
    /// Show session QSO count
    case sessionCount
}

// MARK: - ContestModeValue

/// Contest operating mode for command palette
public enum ContestModeValue: String, Sendable, Equatable {
    case run
    case searchAndPounce
}

// MARK: - SplitDirective

/// Split operation directive
public enum SplitDirective: Sendable, Equatable {
    /// TX offset above RX (default 1 kHz)
    case up(kHz: Double)
    /// TX offset below RX (default 1 kHz)
    case down(kHz: Double)
    /// TX on explicit frequency in kHz
    case explicitFrequency(kHz: Double)
    /// Disable split
    case off
}

// MARK: - RadioParsedToken

/// Individual parsed token with validation state
public struct RadioParsedToken: Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(kind: TokenKind, rawText: String, displayText: String, state: ValidationState) {
        self.kind = kind
        self.rawText = rawText
        self.displayText = displayText
        self.state = state
    }

    // MARK: Public

    public let id = UUID()
    public let kind: TokenKind
    public let rawText: String
    public let displayText: String
    public let state: ValidationState

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.rawText == rhs.rawText && lhs.displayText == rhs.displayText
            && lhs.state == rhs.state
    }
}

// MARK: - TokenKind

public enum TokenKind: Sendable, Equatable {
    case frequency
    case mode
    case band
    case split
    case command
    case unknown
}

// MARK: - ValidationState

public enum ValidationState: Sendable, Equatable {
    case valid
    case warning(String)
    case error(String)
}

// MARK: - RadioCommandParser

/// Parses radio command palette input into structured commands
///
/// Supports order-flexible token parsing:
/// - Frequencies: `14074` (kHz), `14.074` (MHz), band shortcuts (`20m`)
/// - Modes: `CW`, `SSB`, `USB`, `LSB`, `FT8`, `FT4`, `RTTY`, `PSK`, `AM`, `FM`, `DIGI`/`DATA`
/// - Split: `UP [n]`, `DN [n]`/`DOWN [n]`, `SPLIT [freq]`, `NOSPLIT`
public enum RadioCommandParser: Sendable {
    // MARK: Public

    /// All recognized mode keywords
    public static let modeKeywords: Set<String> = [
        "CW", "SSB", "USB", "LSB", "FT8", "FT4", "RTTY",
        "PSK", "PSK31", "AM", "FM", "DIGI", "DATA",
    ]

    /// Parse input string into a RadioCommand and list of parsed tokens
    public static func parse(_ input: String) -> (command: RadioCommand, tokens: [RadioParsedToken]) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return (RadioCommand(), [])
        }

        let rawTokens = tokenize(trimmed)

        // Try named command parse first (keyword at position 0)
        if let result = parseNamedCommand(rawTokens) {
            return result
        }

        // Fall through to radio tuning parse
        var command = RadioCommand()
        var parsedTokens: [RadioParsedToken] = []
        var index = 0

        while index < rawTokens.count {
            let consumed = classifyToken(rawTokens, index, &command, &parsedTokens)
            index += consumed
        }

        resolveBandWithMode(&command, parsedTokens)
        return (command, parsedTokens)
    }

    /// Resolve a mode keyword into a concrete radio mode for a given band
    /// SSB auto-resolves to USB (>= 10 MHz) or LSB (< 10 MHz)
    public static func resolveMode(_ mode: String, frequencyMHz: Double?) -> String {
        let upper = mode.uppercased()
        guard upper == "SSB" else {
            return upper
        }
        guard let freq = frequencyMHz else {
            return "USB"
        }
        return freq >= 10.0 ? "USB" : "LSB"
    }

    // MARK: Private

    // MARK: - Split Parsing

    private struct SplitParseResult {
        let directive: SplitDirective
        let token: RadioParsedToken
        let consumed: Int
    }

    private struct OffsetResult {
        let value: Double
        let consumed: Int
        let rawText: String
    }

    private enum ReferenceKind { case setPark, setSummit }

    private static func classifyToken(
        _ tokens: [String],
        _ index: Int,
        _ command: inout RadioCommand,
        _ parsed: inout [RadioParsedToken]
    ) -> Int {
        let token = tokens[index]
        let upper = token.uppercased()

        if let split = parseSplit(upper, tokens, index) {
            command.splitDirective = split.directive
            parsed.append(split.token)
            return split.consumed
        }

        if let normalizedMode = normalizeMode(upper) {
            parsed.append(RadioParsedToken(kind: .mode, rawText: token, displayText: normalizedMode, state: .valid))
            command.mode = normalizedMode
            return 1
        }

        if let bandResult = RadioBandDefaults.resolve(upper, currentMode: command.mode) {
            command.frequencyMHz = bandResult
            parsed.append(RadioParsedToken(
                kind: .band, rawText: token,
                displayText: "\(upper) \(formatFrequency(bandResult))", state: .valid
            ))
            return 1
        }

        if let freqMHz = FrequencyFormatter.parse(token) {
            command.frequencyMHz = freqMHz
            let bandLabel = BandUtilities.deriveBand(from: freqMHz * 1_000) ?? ""
            let suffix = bandLabel.isEmpty ? "" : " (\(bandLabel))"
            parsed.append(RadioParsedToken(
                kind: .frequency, rawText: token,
                displayText: "\(formatFrequency(freqMHz)) MHz\(suffix)", state: .valid
            ))
            return 1
        }

        parsed.append(RadioParsedToken(kind: .unknown, rawText: token, displayText: token,
                                       state: .error("Unrecognized: \(token)")))
        return 1
    }

    private static func resolveBandWithMode(_ command: inout RadioCommand, _ tokens: [RadioParsedToken]) {
        if let bandToken = tokens.first(where: { $0.kind == .band }),
           let mode = command.mode
        {
            let bandName = bandToken.rawText.uppercased()
            if let resolved = RadioBandDefaults.resolve(bandName, currentMode: mode) {
                command.frequencyMHz = resolved
            }
        }
    }

    // MARK: - Named Command Parsing

    private static func parseNamedCommand(_ tokens: [String]) -> (RadioCommand, [RadioParsedToken])? {
        guard let first = tokens.first else {
            return nil
        }
        let keyword = first.uppercased()
        let args = Array(tokens.dropFirst())
        let raw = tokens.joined(separator: " ")

        switch keyword {
        case "QRZ",
             "?": return parseLookupCommand(args, raw: raw)
        case "SPOT": return parseSpotCommand(args, raw: raw)
        case "PARK": return parseReferenceCommand(args, raw: raw, kind: .setPark)
        case "SUMMIT": return parseReferenceCommand(args, raw: raw, kind: .setSummit)
        case "PWR",
             "POWER": return parsePowerCommand(args, raw: raw)
        case "CQ": return parseCQCommand(raw: raw)
        case "WPM",
             "SPEED": return parseSpeedCommand(args, raw: raw)
        case "RUN": return parseContestModeCommand(.run, raw: raw)
        case "S&P",
             "SP",
             "SAP": return parseContestModeCommand(.searchAndPounce, raw: raw)
        case "FIND": return parseFindCommand(args, raw: raw)
        case "LAST": return parseLastCommand(args, raw: raw)
        case "COUNT": return parseCountCommand(raw: raw)
        default: return nil
        }
    }

    private static func parseLookupCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken])? {
        guard let call = args.first else {
            return nil
        }
        let callsign = call.uppercased()
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Lookup \(callsign)", state: .valid)
        return (RadioCommand(namedCommand: .lookup(callsign: callsign)), [token])
    }

    private static func parseSpotCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken])? {
        guard let call = args.first else {
            return nil
        }
        let callsign = call.uppercased()
        let freq = args.count > 1 ? FrequencyFormatter.parse(args[1]).map { $0 * 1_000 } : nil
        let freqText = freq.map { " on \(formatFrequency($0 / 1_000)) MHz" } ?? ""
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Spot \(callsign)\(freqText) to cluster", state: .valid)
        return (RadioCommand(namedCommand: .spot(callsign: callsign, frequencyKHz: freq)), [token])
    }

    private static func parseReferenceCommand(
        _ args: [String], raw: String, kind: ReferenceKind
    ) -> (RadioCommand, [RadioParsedToken])? {
        guard let ref = args.first else {
            return nil
        }
        let reference = ref.uppercased()
        let label = kind == .setPark ? "park" : "summit"
        let named: NamedCommand = kind == .setPark ? .setPark(reference: reference) : .setSummit(reference: reference)
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Set \(label) \(reference)", state: .valid)
        return (RadioCommand(namedCommand: named), [token])
    }

    private static func parsePowerCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken])? {
        guard let arg = args.first else {
            return nil
        }
        let watts: Int? = arg.uppercased() == "QRP" ? 5 : Int(arg)
        guard let validWatts = watts, validWatts > 0, validWatts <= 1_500 else {
            return nil
        }
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Set power \(validWatts)W", state: .valid)
        return (RadioCommand(namedCommand: .setPower(watts: validWatts)), [token])
    }

    private static func tokenize(_ input: String) -> [String] {
        input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    private static func normalizeMode(_ token: String) -> String? {
        let upper = token.uppercased()
        guard modeKeywords.contains(upper) else {
            return nil
        }
        switch upper {
        case "PSK31": return "PSK"
        case "DIGI": return "DATA"
        default: return upper
        }
    }

    private static func parseSplit(
        _ upper: String,
        _ tokens: [String],
        _ index: Int
    ) -> SplitParseResult? {
        switch upper {
        case "UP":
            let result = parseOptionalOffset(tokens, index)
            return SplitParseResult(
                directive: .up(kHz: result.value),
                token: splitToken(rawText: result.rawText, display: "TX +\(formatOffset(result.value)) kHz"),
                consumed: result.consumed
            )

        case "DN",
             "DOWN":
            let result = parseOptionalOffset(tokens, index)
            return SplitParseResult(
                directive: .down(kHz: result.value),
                token: splitToken(rawText: result.rawText, display: "TX -\(formatOffset(result.value)) kHz"),
                consumed: result.consumed
            )

        case "SPLIT":
            guard index + 1 < tokens.count, let freqKHz = Double(tokens[index + 1]) else {
                return nil
            }
            return SplitParseResult(
                directive: .explicitFrequency(kHz: freqKHz),
                token: splitToken(rawText: "\(tokens[index]) \(tokens[index + 1])",
                                  display: "TX \(formatFrequency(freqKHz / 1_000)) MHz"),
                consumed: 2
            )

        case "NOSPLIT":
            return SplitParseResult(
                directive: .off,
                token: splitToken(rawText: "NOSPLIT", display: "Split OFF"),
                consumed: 1
            )

        default:
            return nil
        }
    }

    private static func splitToken(rawText: String, display: String) -> RadioParsedToken {
        RadioParsedToken(kind: .split, rawText: rawText, displayText: display, state: .valid)
    }

    private static func parseOptionalOffset(_ tokens: [String], _ index: Int) -> OffsetResult {
        if index + 1 < tokens.count, let value = Double(tokens[index + 1]),
           value > 0, value <= 100
        {
            return OffsetResult(value: value, consumed: 2, rawText: "\(tokens[index]) \(tokens[index + 1])")
        }
        return OffsetResult(value: 1.0, consumed: 1, rawText: tokens[index])
    }

    // MARK: - Phase 3 Command Parsing

    private static func parseCQCommand(raw: String) -> (RadioCommand, [RadioParsedToken]) {
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Send CQ (F1)", state: .valid)
        return (RadioCommand(namedCommand: .sendCQ), [token])
    }

    private static func parseSpeedCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken])? {
        guard let arg = args.first, let wpm = Int(arg), wpm >= 5, wpm <= 60 else {
            return nil
        }
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Set CW speed \(wpm) WPM", state: .valid)
        return (RadioCommand(namedCommand: .setSpeed(wpm: wpm)), [token])
    }

    private static func parseContestModeCommand(
        _ mode: ContestModeValue, raw: String
    ) -> (RadioCommand, [RadioParsedToken]) {
        let label = mode == .run ? "RUN" : "S&P"
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Set contest mode: \(label)", state: .valid)
        return (RadioCommand(namedCommand: .setContestMode(mode: mode)), [token])
    }

    private static func parseFindCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken])? {
        guard let call = args.first else {
            return nil
        }
        let callsign = call.uppercased()
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Search log for \(callsign)", state: .valid)
        return (RadioCommand(namedCommand: .findCall(callsign: callsign)), [token])
    }

    private static func parseLastCommand(_ args: [String], raw: String) -> (RadioCommand, [RadioParsedToken]) {
        let count = max(1, min(args.first.flatMap(Int.init) ?? 10, 100))
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Show last \(count) QSOs", state: .valid)
        return (RadioCommand(namedCommand: .lastQSOs(count: count)), [token])
    }

    private static func parseCountCommand(raw: String) -> (RadioCommand, [RadioParsedToken]) {
        let token = RadioParsedToken(kind: .command, rawText: raw,
                                     displayText: "Session QSO count", state: .valid)
        return (RadioCommand(namedCommand: .sessionCount), [token])
    }

    // MARK: - Formatting Helpers

    private static func formatFrequency(_ mhz: Double) -> String {
        FrequencyFormatter.format(mhz)
    }

    private static func formatOffset(_ kHz: Double) -> String {
        kHz == kHz.rounded() ? String(Int(kHz)) : String(format: "%.1f", kHz)
    }
}
