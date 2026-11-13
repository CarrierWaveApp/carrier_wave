//
//  QuickEntryParser.swift
//  CarrierWaveCore
//
//  The quick-entry grammar lives in the Rust core (`cw_domain::quick_entry`)
//  and is shared with Android through the same UniFFI surface. This file keeps
//  the Swift-native public types the UI depends on and forwards every parse
//  through Rust, lifting the FFI DTOs back into those Swift types. Parity is the
//  acceptance bar — the canonical tests now live in `cw-domain`.
//

import CarrierWaveCwFfi
import Foundation

// MARK: - RSTOrder

/// Controls the default order of unsuffixed RST values in quick entry.
public enum RSTOrder: String, CaseIterable, Equatable, Sendable {
    /// First RST = received, second = sent (default, matches POTA convention).
    case receivedFirst
    /// First RST = sent, second = received (matches contest convention).
    case sentFirst

    // MARK: Public

    public var label: String {
        switch self {
        case .receivedFirst: "Received first"
        case .sentFirst: "Sent first"
        }
    }
}

// MARK: - RSTConflict

/// Describes a conflict when parsing RST values with explicit suffixes.
public enum RSTConflict: Equatable, Sendable {
    case duplicateReceived
    case duplicateSent
}

// MARK: - TokenType

/// Token types for quick entry color coding.
public enum TokenType: Equatable, Sendable {
    case callsign
    case rstSent
    case rstReceived
    case state
    case park
    case grid
    case frequency
    case band
    case mode
    case notes
    /// UTC time override (e.g., 1804Z).
    case time
    /// RST value that conflicts with another (duplicate R or S suffix).
    case rstConflict
}

// MARK: - ParsedToken

/// A parsed token with its text and type for UI preview.
public struct ParsedToken: Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(index: Int, text: String, type: TokenType) {
        self.index = index
        self.text = text
        self.type = type
    }

    // MARK: Public

    /// Position in the token list (used for stable SwiftUI identity).
    public let index: Int
    public let text: String
    public let type: TokenType

    /// Stable ID based on position to prevent view hierarchy rebuild during typing.
    public var id: Int {
        index
    }
}

// MARK: - QuickEntryResult

/// Result of parsing a quick entry string.
public struct QuickEntryResult: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        callsign: String,
        rstSent: String? = nil,
        rstReceived: String? = nil,
        state: String? = nil,
        theirPark: String? = nil,
        theirGrid: String? = nil,
        frequency: Double? = nil,
        band: String? = nil,
        mode: String? = nil,
        notes: String? = nil,
        rstConflicts: [RSTConflict] = [],
        zuluTime: ZuluTime? = nil
    ) {
        self.callsign = callsign
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.state = state
        self.theirPark = theirPark
        self.theirGrid = theirGrid
        self.frequency = frequency
        self.band = band
        self.mode = mode
        self.notes = notes
        self.rstConflicts = rstConflicts
        self.zuluTime = zuluTime
    }

    // MARK: Public

    public let callsign: String
    public var rstSent: String?
    public var rstReceived: String?
    public var state: String?
    public var theirPark: String?
    public var theirGrid: String?
    public var frequency: Double?
    public var band: String?
    public var mode: String?
    public var notes: String?

    /// Conflicts detected during RST parsing (e.g., duplicate R or S suffixes).
    public var rstConflicts: [RSTConflict] = []

    /// UTC time override parsed from a Z-suffix token (e.g., 1804Z).
    public var zuluTime: ZuluTime?
}

// MARK: - ZuluTime

/// A UTC time parsed from a Z-suffix token (e.g., "1804Z" → hour: 18, minute: 04).
public struct ZuluTime: Equatable, Sendable {
    // MARK: Lifecycle

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    // MARK: Public

    public let hour: Int
    public let minute: Int

    /// Build a Date by applying this time to today's date in UTC.
    public func dateToday() -> Date {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!
        var dcomps = cal.dateComponents([.year, .month, .day], from: Date())
        dcomps.hour = hour
        dcomps.minute = minute
        dcomps.second = 0
        dcomps.timeZone = TimeZone(identifier: "UTC")
        return cal.date(from: dcomps) ?? Date()
    }
}

// MARK: - SessionMetadataEntry

/// Session-metadata updates parsed from a callsign-less logger line (e.g.
/// "14.046 CW"). Applies to the active session — future QSOs, not a single log.
public struct SessionMetadataEntry: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        frequency: Double? = nil,
        band: String? = nil,
        mode: String? = nil,
        grid: String? = nil,
        unsupported: [String] = []
    ) {
        self.frequency = frequency
        self.band = band
        self.mode = mode
        self.grid = grid
        self.unsupported = unsupported
    }

    // MARK: Public

    public let frequency: Double?
    public let band: String?
    public let mode: String?
    public let grid: String?

    /// Tokens the session can't take (parks, states, RSTs, times, free text) —
    /// surface these to the user instead of silently dropping them.
    public let unsupported: [String]
}

// MARK: - RSTSuffix

/// Result of checking an RST token for an explicit R/S suffix.
public enum RSTSuffix: Equatable {
    case none
    case received
    case sent
}

// MARK: - QuickEntryParser

/// Parses quick entry strings like "AJ7CM 579 WA US-0189" into structured data.
///
/// Every method forwards to `cw_domain::quick_entry` via UniFFI so iOS, macOS,
/// and Android share one grammar implementation.
public enum QuickEntryParser: Sendable {
    // MARK: Public

    // MARK: Parsing

    /// Parse a quick entry string into a structured result. Returns nil if the
    /// input isn't valid quick entry (single callsign / first token is a command).
    public static func parse(
        _ input: String,
        rstOrder: RSTOrder = .receivedFirst,
        isCommand: ((String) -> Bool)? = nil
    ) -> QuickEntryResult? {
        if isFirstTokenCommand(input, isCommand) {
            return nil
        }
        return parseQuickEntry(input: input, rstOrder: lower(rstOrder)).map(lift)
    }

    /// Parse a quick entry string that may contain multiple callsigns. Each
    /// callsign gets its own result sharing the same metadata.
    public static func parseMulti(
        _ input: String,
        rstOrder: RSTOrder = .receivedFirst,
        isCommand: ((String) -> Bool)? = nil
    ) -> [QuickEntryResult]? {
        if isFirstTokenCommand(input, isCommand) {
            return nil
        }
        return parseQuickEntryMulti(input: input, rstOrder: lower(rstOrder))?.map(lift)
    }

    /// Parse a quick entry string into typed tokens for the color-coded preview.
    public static func parseTokens(
        _ input: String,
        rstOrder: RSTOrder = .receivedFirst,
        isCommand: ((String) -> Bool)? = nil
    ) -> [ParsedToken] {
        if isFirstTokenCommand(input, isCommand) {
            return []
        }
        return parseQuickEntryTokens(input: input, rstOrder: lower(rstOrder)).map(lift)
    }

    /// Parse a multi-callsign quick entry string into preview tokens.
    public static func parseMultiTokens(
        _ input: String,
        rstOrder: RSTOrder = .receivedFirst,
        isCommand: ((String) -> Bool)? = nil
    ) -> [ParsedToken] {
        if isFirstTokenCommand(input, isCommand) {
            return []
        }
        return parseQuickEntryMultiTokens(input: input, rstOrder: lower(rstOrder)).map(lift)
    }

    /// Parse a callsign-less line (e.g. "14.046 CW") into session-metadata
    /// updates, or nil when the line contains a callsign or no settable field.
    public static func parseSessionMetadata(_ input: String) -> SessionMetadataEntry? {
        parseQuickEntrySessionMetadata(input: input).map(lift)
    }

    // MARK: Token predicates

    public static func isRST(_ string: String) -> Bool {
        quickEntryIsRst(value: string)
    }

    public static func isCallsign(_ string: String) -> Bool {
        quickEntryIsCallsign(value: string)
    }

    public static func isParkReference(_ string: String) -> Bool {
        quickEntryIsParkReference(value: string)
    }

    public static func isGridSquare(_ string: String) -> Bool {
        quickEntryIsGridSquare(value: string)
    }

    public static func isStateOrRegion(_ string: String) -> Bool {
        quickEntryIsStateOrRegion(value: string)
    }

    public static func isMode(_ string: String) -> Bool {
        quickEntryIsMode(value: string)
    }

    /// Strip R/S suffix from an RST token and return the numeric value and suffix.
    public static func stripRSTSuffix(_ string: String) -> (value: String, suffix: RSTSuffix) {
        let stripped = quickEntryStripRstSuffix(value: string)
        return (stripped.value, lift(stripped.suffix))
    }

    public static func isZuluTime(_ string: String) -> Bool {
        quickEntryParseZuluTime(value: string) != nil
    }

    /// Parse a UTC time token (`HH:MM`, `HHMMZ`, …). Returns nil if no match.
    public static func parseZuluTime(_ string: String) -> ZuluTime? {
        quickEntryParseZuluTime(value: string).map(lift)
    }

    /// Lift a Rust `FfiQuickEntry` into a `QuickEntryResult` — public so
    /// `LoggerCommand` can lift the HUNT one-off-log entry the shared command
    /// parser returns.
    public static func result(from entry: FfiQuickEntry) -> QuickEntryResult {
        lift(entry)
    }

    /// Lift a Rust `FfiSessionMetadataEntry` into a `SessionMetadataEntry`.
    public static func metadata(from entry: FfiSessionMetadataEntry) -> SessionMetadataEntry {
        lift(entry)
    }

    // MARK: Private

    // MARK: Command pre-check

    /// Mirrors the Swift-side command guard: a line whose first token is a logger
    /// command (e.g. "FREQ", "MODE") is not quick entry. The grammar itself lives
    /// in Rust, but command vocabulary is app-defined, so it's checked here.
    private static func isFirstTokenCommand(_ input: String, _ isCommand: ((String) -> Bool)?) -> Bool {
        guard let isCommand,
              let first = input.uppercased().split(separator: " ", omittingEmptySubsequences: true).first
        else {
            return false
        }
        return isCommand(String(first))
    }

    // MARK: FFI lifting

    private static func lower(_ order: RSTOrder) -> FfiRstOrder {
        switch order {
        case .receivedFirst: .receivedFirst
        case .sentFirst: .sentFirst
        }
    }

    private static func lift(_ entry: FfiQuickEntry) -> QuickEntryResult {
        QuickEntryResult(
            callsign: entry.callsign,
            rstSent: entry.rstSent,
            rstReceived: entry.rstReceived,
            state: entry.state,
            theirPark: entry.theirPark,
            theirGrid: entry.theirGrid,
            frequency: entry.frequency,
            band: entry.band,
            mode: entry.mode,
            notes: entry.notes,
            rstConflicts: entry.rstConflicts.map(lift),
            zuluTime: entry.zuluTime.map(lift)
        )
    }

    private static func lift(_ entry: FfiSessionMetadataEntry) -> SessionMetadataEntry {
        SessionMetadataEntry(
            frequency: entry.frequency,
            band: entry.band,
            mode: entry.mode,
            grid: entry.grid,
            unsupported: entry.unsupported
        )
    }

    private static func lift(_ token: FfiQuickToken) -> ParsedToken {
        ParsedToken(index: Int(token.index), text: token.text, type: lift(token.tokenType))
    }

    private static func lift(_ type: FfiQuickTokenType) -> TokenType {
        switch type {
        case .callsign: .callsign
        case .rstSent: .rstSent
        case .rstReceived: .rstReceived
        case .state: .state
        case .park: .park
        case .grid: .grid
        case .frequency: .frequency
        case .band: .band
        case .mode: .mode
        case .notes: .notes
        case .time: .time
        case .rstConflict: .rstConflict
        }
    }

    private static func lift(_ conflict: FfiRstConflict) -> RSTConflict {
        switch conflict {
        case .duplicateReceived: .duplicateReceived
        case .duplicateSent: .duplicateSent
        }
    }

    private static func lift(_ time: FfiZuluTime) -> ZuluTime {
        ZuluTime(hour: Int(time.hour), minute: Int(time.minute))
    }

    private static func lift(_ suffix: FfiRstSuffix) -> RSTSuffix {
        switch suffix {
        case .none: .none
        case .received: .received
        case .sent: .sent
        }
    }
}
