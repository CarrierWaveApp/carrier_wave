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
        splitDirective: SplitDirective? = nil
    ) {
        self.frequencyMHz = frequencyMHz
        self.mode = mode
        self.splitDirective = splitDirective
    }

    // MARK: Public

    public var frequencyMHz: Double?
    public var mode: String?
    public var splitDirective: SplitDirective?

    public var isEmpty: Bool {
        frequencyMHz == nil && mode == nil && splitDirective == nil
    }
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

// MARK: - ParsedToken

/// Individual parsed token with validation state
public struct ParsedToken: Sendable, Equatable, Identifiable {
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

    public static func == (lhs: ParsedToken, rhs: ParsedToken) -> Bool {
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
    public static func parse(_ input: String) -> (command: RadioCommand, tokens: [ParsedToken]) {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return (RadioCommand(), [])
        }

        let rawTokens = tokenize(trimmed)
        var command = RadioCommand()
        var parsedTokens: [ParsedToken] = []
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

    // MARK: - Band Shortcuts

    private struct BandResolution {
        let frequencyMHz: Double
    }

    private struct BandDefault {
        let cw: Double
        let ssb: Double
        let ft8: Double
        let ft4: Double?
    }

    // MARK: - Split Parsing

    private struct SplitParseResult {
        let directive: SplitDirective
        let token: ParsedToken
        let consumed: Int
    }

    private struct OffsetResult {
        let value: Double
        let consumed: Int
        let rawText: String
    }

    private static let bandDefaults: [String: BandDefault] = [
        "160M": BandDefault(cw: 1.810, ssb: 1.900, ft8: 1.840, ft4: 1.840),
        "80M": BandDefault(cw: 3.530, ssb: 3.800, ft8: 3.573, ft4: 3.575),
        "60M": BandDefault(cw: 5.332, ssb: 5.332, ft8: 5.357, ft4: nil),
        "40M": BandDefault(cw: 7.030, ssb: 7.200, ft8: 7.074, ft4: 7.047),
        "30M": BandDefault(cw: 10.110, ssb: 10.110, ft8: 10.136, ft4: 10.140),
        "20M": BandDefault(cw: 14.030, ssb: 14.250, ft8: 14.074, ft4: 14.080),
        "17M": BandDefault(cw: 18.080, ssb: 18.130, ft8: 18.100, ft4: 18.104),
        "15M": BandDefault(cw: 21.030, ssb: 21.300, ft8: 21.074, ft4: 21.140),
        "12M": BandDefault(cw: 24.900, ssb: 24.950, ft8: 24.915, ft4: 24.919),
        "10M": BandDefault(cw: 28.030, ssb: 28.500, ft8: 28.074, ft4: 28.180),
        "6M": BandDefault(cw: 50.090, ssb: 50.150, ft8: 50.313, ft4: 50.318),
        "2M": BandDefault(cw: 144.050, ssb: 144.200, ft8: 144.174, ft4: 144.170),
    ]

    private static func classifyToken(
        _ tokens: [String],
        _ index: Int,
        _ command: inout RadioCommand,
        _ parsed: inout [ParsedToken]
    ) -> Int {
        let token = tokens[index]
        let upper = token.uppercased()

        if let split = parseSplit(upper, tokens, index) {
            command.splitDirective = split.directive
            parsed.append(split.token)
            return split.consumed
        }

        if let normalizedMode = normalizeMode(upper) {
            parsed.append(ParsedToken(kind: .mode, rawText: token, displayText: normalizedMode, state: .valid))
            command.mode = normalizedMode
            return 1
        }

        if let bandResult = parseBandShortcut(upper, currentMode: command.mode) {
            command.frequencyMHz = bandResult.frequencyMHz
            parsed.append(ParsedToken(
                kind: .band, rawText: token,
                displayText: "\(upper) \(formatFrequency(bandResult.frequencyMHz))", state: .valid
            ))
            return 1
        }

        if let freqMHz = FrequencyFormatter.parse(token) {
            command.frequencyMHz = freqMHz
            let bandLabel = BandUtilities.deriveBand(from: freqMHz * 1_000) ?? ""
            let suffix = bandLabel.isEmpty ? "" : " (\(bandLabel))"
            parsed.append(ParsedToken(
                kind: .frequency, rawText: token,
                displayText: "\(formatFrequency(freqMHz)) MHz\(suffix)", state: .valid
            ))
            return 1
        }

        parsed.append(ParsedToken(kind: .unknown, rawText: token, displayText: token,
                                  state: .error("Unrecognized: \(token)")))
        return 1
    }

    private static func resolveBandWithMode(_ command: inout RadioCommand, _ tokens: [ParsedToken]) {
        if let bandToken = tokens.first(where: { $0.kind == .band }),
           let mode = command.mode
        {
            let bandName = bandToken.rawText.uppercased()
            if let resolved = parseBandShortcut(bandName, currentMode: mode) {
                command.frequencyMHz = resolved.frequencyMHz
            }
        }
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

    private static func splitToken(rawText: String, display: String) -> ParsedToken {
        ParsedToken(kind: .split, rawText: rawText, displayText: display, state: .valid)
    }

    private static func parseOptionalOffset(_ tokens: [String], _ index: Int) -> OffsetResult {
        if index + 1 < tokens.count, let value = Double(tokens[index + 1]),
           value > 0, value <= 100
        {
            return OffsetResult(value: value, consumed: 2, rawText: "\(tokens[index]) \(tokens[index + 1])")
        }
        return OffsetResult(value: 1.0, consumed: 1, rawText: tokens[index])
    }

    private static func parseBandShortcut(
        _ token: String,
        currentMode: String?
    ) -> BandResolution? {
        guard let defaults = bandDefaults[token] else {
            return nil
        }

        let mode = currentMode?.uppercased() ?? "CW"
        let freqMHz: Double = switch mode {
        case "FT8":
            defaults.ft8
        case "FT4":
            defaults.ft4 ?? defaults.ft8
        case "SSB",
             "USB",
             "LSB",
             "AM",
             "FM":
            defaults.ssb
        default:
            defaults.cw
        }

        return BandResolution(frequencyMHz: freqMHz)
    }

    // MARK: - Formatting Helpers

    private static func formatFrequency(_ mhz: Double) -> String {
        FrequencyFormatter.format(mhz)
    }

    private static func formatOffset(_ kHz: Double) -> String {
        kHz == kHz.rounded() ? String(Int(kHz)) : String(format: "%.1f", kHz)
    }
}
