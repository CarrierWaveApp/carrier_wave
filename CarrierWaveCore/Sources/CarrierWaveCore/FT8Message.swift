//
//  FT8Message.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - FT8Message

/// Parsed FT8 message types representing the standard QSO exchange sequence
public enum FT8Message: Sendable, Equatable, Hashable {
    /// CQ call with optional modifier (POTA, DX, etc.)
    case cq(call: String, grid: String, modifier: String?)

    /// Response to CQ with grid locator
    case directed(from: String, to: String, grid: String)

    /// Signal report (e.g. -12)
    case signalReport(from: String, to: String, dB: Int)

    /// Roger + signal report (e.g. R-07)
    case rogerReport(from: String, to: String, dB: Int)

    /// RRR acknowledgment
    case roger(from: String, to: String)

    /// RR73 — completes QSO
    case rogerEnd(from: String, to: String)

    /// 73 — completes QSO
    case end(from: String, to: String)

    /// Free text message (up to 13 characters)
    case freeText(String)
}

// MARK: - Computed Properties

public extension FT8Message {
    /// Whether this message can be responded to (only CQ calls)
    var isCallable: Bool {
        if case .cq = self {
            return true
        }
        return false
    }

    /// Whether this message signals QSO completion
    var completesQSO: Bool {
        switch self {
        case .rogerEnd,
             .end: true
        default: false
        }
    }

    /// The originating callsign, if applicable
    var callerCallsign: String? {
        switch self {
        case let .cq(call, _, _): call
        case let .directed(from, _, _): from
        case let .signalReport(from, _, _): from
        case let .rogerReport(from, _, _): from
        case let .roger(from, _): from
        case let .rogerEnd(from, _): from
        case let .end(from, _): from
        case .freeText: nil
        }
    }

    /// Grid locator from CQ or directed messages, nil if empty or absent
    var grid: String? {
        switch self {
        case let .cq(_, grid, _):
            grid.isEmpty ? nil : grid
        case let .directed(_, _, grid):
            grid.isEmpty ? nil : grid
        default:
            nil
        }
    }

    /// CQ modifier (POTA, DX, etc.), only present on CQ messages
    var cqModifier: String? {
        if case let .cq(_, _, modifier) = self {
            return modifier
        }
        return nil
    }

    /// Whether this message is directed to the specified callsign (case-insensitive)
    func isDirectedTo(_ callsign: String) -> Bool {
        let target = callsign.uppercased()
        switch self {
        case let .directed(_, to, _): return to.uppercased() == target
        case let .signalReport(_, to, _): return to.uppercased() == target
        case let .rogerReport(_, to, _): return to.uppercased() == target
        case let .roger(_, to): return to.uppercased() == target
        case let .rogerEnd(_, to): return to.uppercased() == target
        case let .end(_, to): return to.uppercased() == target
        default: return false
        }
    }
}

// MARK: - Parsing

extension FT8Message {
    /// Parses raw FT8 message text into a typed message
    ///
    /// Recognized formats:
    /// - `CQ CALL GRID` or `CQ MODIFIER CALL GRID`
    /// - `TOCALL FROMCALL GRID` (4-char grid: letter-letter-digit-digit)
    /// - `TOCALL FROMCALL {+/-}NN` (signal report)
    /// - `TOCALL FROMCALL R{+/-}NN` (roger + report)
    /// - `TOCALL FROMCALL RRR`
    /// - `TOCALL FROMCALL RR73`
    /// - `TOCALL FROMCALL 73`
    /// - Everything else → `.freeText`
    public static func parse(_ text: String) -> FT8Message {
        let tokens = text.split(separator: " ").map(String.init)

        // CQ messages
        if tokens.first == "CQ" {
            return parseCQ(tokens: tokens)
        }

        // Three-token directed messages: TOCALL FROMCALL PAYLOAD
        if tokens.count == 3 {
            return parseDirectedThreeToken(tokens: tokens)
        }

        // Anything else is free text
        return .freeText(text)
    }

    // MARK: - Private Parsing Helpers

    private static func parseCQ(tokens: [String]) -> FT8Message {
        // "CQ CALL GRID" (3 tokens)
        if tokens.count == 3 {
            return .cq(call: tokens[1], grid: tokens[2], modifier: nil)
        }
        // "CQ MODIFIER CALL GRID" (4 tokens)
        if tokens.count == 4 {
            return .cq(call: tokens[2], grid: tokens[3], modifier: tokens[1])
        }
        // CQ with 1 token (bare "CQ") or 5+ tokens doesn't match standard FT8 formats
        return .freeText(tokens.joined(separator: " "))
    }

    private static func parseDirectedThreeToken(tokens: [String]) -> FT8Message {
        let toCall = tokens[0]
        let fromCall = tokens[1]
        let payload = tokens[2]

        // RR73
        if payload == "RR73" {
            return .rogerEnd(from: fromCall, to: toCall)
        }
        // RRR
        if payload == "RRR" {
            return .roger(from: fromCall, to: toCall)
        }
        // 73
        if payload == "73" {
            return .end(from: fromCall, to: toCall)
        }
        // R{+/-}NN roger report
        if let dB = parseRogerReport(payload) {
            return .rogerReport(from: fromCall, to: toCall, dB: dB)
        }
        // {+/-}NN signal report
        if let dB = parseSignalReport(payload) {
            return .signalReport(from: fromCall, to: toCall, dB: dB)
        }
        // 4-char grid (letter-letter-digit-digit)
        if isGrid(payload) {
            return .directed(from: fromCall, to: toCall, grid: payload)
        }

        return .freeText(tokens.joined(separator: " "))
    }

    /// Checks if a string matches the Maidenhead grid field pattern (e.g. FN42)
    /// Valid grids are two letters A-R followed by two digits
    private static func isGrid(_ text: String) -> Bool {
        guard text.count == 4 else {
            return false
        }
        let upper = text.uppercased()
        let chars = Array(upper)
        return ("A" ... "R").contains(chars[0]) && ("A" ... "R").contains(chars[1])
            && chars[2].isNumber && chars[3].isNumber
    }

    /// Parses a signal report string like "-11" or "+05" into a dB value
    private static func parseSignalReport(_ text: String) -> Int? {
        guard text.count >= 2,
              let first = text.first,
              first == "+" || first == "-"
        else {
            return nil
        }
        return Int(text)
    }

    /// Parses a roger report string like "R-07" or "R+03" into a dB value
    private static func parseRogerReport(_ text: String) -> Int? {
        guard text.hasPrefix("R"), text.count >= 3 else {
            return nil
        }
        let afterR = String(text.dropFirst())
        return parseSignalReport(afterR)
    }
}

// MARK: - FT8DecodeResult

/// Result from decoding an FT8 signal, combining the parsed message with signal metadata
public struct FT8DecodeResult: Sendable, Identifiable {
    // MARK: Lifecycle

    public init(message: FT8Message, snr: Int, deltaTime: Double, frequency: Double, rawText: String) {
        self.message = message
        self.snr = snr
        self.deltaTime = deltaTime
        self.frequency = frequency
        self.rawText = rawText
    }

    // MARK: Public

    /// Stable identity for SwiftUI diffing (excluded from equality).
    public let id = UUID()

    /// The parsed FT8 message
    public let message: FT8Message

    /// Signal-to-noise ratio in dB
    public let snr: Int

    /// Time offset from slot boundary in seconds
    public let deltaTime: Double

    /// Audio frequency offset from dial frequency in Hz
    public let frequency: Double

    /// Original undecoded message text
    public let rawText: String
}

// MARK: Equatable

/// Manual Equatable: two results with the same content are equal regardless of `id`.
extension FT8DecodeResult: Equatable {
    public static func == (lhs: FT8DecodeResult, rhs: FT8DecodeResult) -> Bool {
        lhs.message == rhs.message
            && lhs.snr == rhs.snr
            && lhs.deltaTime == rhs.deltaTime
            && lhs.frequency == rhs.frequency
            && lhs.rawText == rhs.rawText
    }
}
