import Foundation

// MARK: - QueryToken

/// Token types produced by the query lexer
public enum QueryToken: Equatable, Sendable {
    /// Field qualifier (e.g., "band:", "mode:", "call:")
    case field(QueryField)

    /// A value (text after field qualifier or bare term)
    case value(String)

    /// OR operator (|)
    case or

    /// NOT operator (-)
    case not

    /// Open parenthesis for grouping
    case openParen

    /// Close parenthesis for grouping
    case closeParen

    /// Range operator (..)
    case range

    /// Comparison operators
    case greaterThan
    case lessThan
    case greaterThanOrEqual
    case lessThanOrEqual

    /// End of input
    case eof
}

// MARK: - QueryField

/// Searchable fields in QSO records
public enum QueryField: String, CaseIterable, Sendable {
    // Core identification
    case callsign = "call"
    case band
    case mode
    case frequency = "freq"

    // Location
    case park
    case sota
    case grid
    case state
    case country
    case dxcc

    // Contact info
    case name
    case qth
    case notes

    // My station
    case myCallsign = "mycall"
    case myGrid = "mygrid"

    // Time
    case date
    case after
    case before

    /// Power
    case power

    // Confirmation/sync status
    case confirmed
    case synced
    case pending
    case source

    // MARK: Public

    /// All recognized aliases for field names
    public static let aliases: [String: QueryField] = [
        // Primary names
        "call": .callsign,
        "callsign": .callsign,
        "band": .band,
        "mode": .mode,
        "freq": .frequency,
        "frequency": .frequency,
        "park": .park,
        "pota": .park,
        "sota": .sota,
        "grid": .grid,
        "state": .state,
        "country": .country,
        "dxcc": .dxcc,
        "name": .name,
        "op": .name,
        "qth": .qth,
        "notes": .notes,
        "mycall": .myCallsign,
        "mygrid": .myGrid,
        "date": .date,
        "on": .date,
        "after": .after,
        "since": .after,
        "from": .after,
        "before": .before,
        "until": .before,
        "to": .before,
        "power": .power,
        "confirmed": .confirmed,
        "synced": .synced,
        "pending": .pending,
        "source": .source,
    ]

    /// Display name for error messages
    public var displayName: String {
        switch self {
        case .callsign: "callsign"
        case .band: "band"
        case .mode: "mode"
        case .frequency: "frequency"
        case .park: "park"
        case .sota: "sota"
        case .grid: "grid"
        case .state: "state"
        case .country: "country"
        case .dxcc: "dxcc"
        case .name: "name"
        case .qth: "qth"
        case .notes: "notes"
        case .myCallsign: "mycall"
        case .myGrid: "mygrid"
        case .date: "date"
        case .after: "after"
        case .before: "before"
        case .power: "power"
        case .confirmed: "confirmed"
        case .synced: "synced"
        case .pending: "pending"
        case .source: "source"
        }
    }

    /// Whether this field is indexed for fast lookups
    public var isIndexed: Bool {
        switch self {
        case .callsign,
             .band,
             .mode,
             .park,
             .date,
             .after,
             .before:
            true
        default:
            false
        }
    }

    /// Whether this field requires text scanning (slow)
    public var requiresTextScan: Bool {
        switch self {
        case .notes,
             .name,
             .qth:
            true
        default:
            false
        }
    }

    /// Parse a field name (case-insensitive)
    public static func parse(_ name: String) -> QueryField? {
        aliases[name.lowercased()]
    }
}

// MARK: - SourcePosition

/// Position in source string for error reporting
public struct SourcePosition: Sendable {
    // MARK: Lifecycle

    public init(offset: Int, length: Int) {
        self.offset = offset
        self.length = length
    }

    // MARK: Public

    public static let unknown = SourcePosition(offset: 0, length: 0)

    public let offset: Int
    public let length: Int

    // swiftformat:disable all
    // Explicit nonisolated Equatable to avoid Swift 6 actor isolation inference
    nonisolated public static func == (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
        lhs.offset == rhs.offset && lhs.length == rhs.length
    }
    // swiftformat:enable all
}

// MARK: Equatable

extension SourcePosition: Equatable {}

// MARK: - PositionedToken

/// Token with source position for error reporting
public struct PositionedToken: Equatable, Sendable {
    // MARK: Lifecycle

    public init(token: QueryToken, position: SourcePosition, rawText: String) {
        self.token = token
        self.position = position
        self.rawText = rawText
    }

    // MARK: Public

    public let token: QueryToken
    public let position: SourcePosition
    public let rawText: String
}
