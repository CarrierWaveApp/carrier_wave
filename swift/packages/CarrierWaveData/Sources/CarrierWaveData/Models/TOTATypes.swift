// TOTA-specific value types stored alongside `LoggingSession`.
//
// The `TOTACategory` enum splits Standard/Mobile (separate leaderboards, separate
// formulas). `T3Candidate` records a Tile-to-Tile QSO candidate derived from
// correlating worked callsigns against the TOTA spots feed at session end.

import Foundation

// MARK: - TOTACategory

/// TOTA leaderboard category. Standard runs the full formula (distance × QSOs +
/// bonuses); Mobile collapses to QSOs × QRP + flats with no distance multiplier.
public enum TOTACategory: String, CaseIterable, Codable, Sendable {
    case standard
    case mobile

    // MARK: Public

    public var displayName: String {
        switch self {
        case .standard: "Standard"
        case .mobile: "Mobile"
        }
    }

    public var icon: String {
        switch self {
        case .standard: "figure.walk"
        case .mobile: "car.fill"
        }
    }
}

// MARK: - T3Candidate

/// A Tile-to-Tile contact candidate derived from spot correlation. Persisted
/// in `LoggingSession.totaT3CandidatesData` once at session end so the summary
/// log doesn't depend on the spots feed (which only reaches back ~168h).
public struct T3Candidate: Codable, Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        callsign: String,
        theirTile: String,
        qsoId: UUID?,
        spotCreatedAt: Date
    ) {
        self.id = id
        self.callsign = callsign
        self.theirTile = theirTile
        self.qsoId = qsoId
        self.spotCreatedAt = spotCreatedAt
    }

    // MARK: Public

    public let id: UUID
    public let callsign: String
    /// 6-char Maidenhead tile reported by the chaser's most recent qualifying spot.
    public let theirTile: String
    /// QSO this candidate corresponds to. nil if we matched a spot without a QSO.
    public let qsoId: UUID?
    public let spotCreatedAt: Date
}
