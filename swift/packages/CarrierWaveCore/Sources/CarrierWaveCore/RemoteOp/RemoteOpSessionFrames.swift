import Foundation

// Wire-format types for the `activeSession` topic. Carries enough of a
// LoggingSession to drive UI continuity between Field and Sweep on the
// LAN — the full property bag still flows over CloudKit. Field/Sweep
// each apply incoming snapshots via the same "most-recent-startedAt
// wins" rule used by the CloudKit journal engine.

// MARK: - RemoteSessionState

/// Snapshot of a logging session as carried over the LAN. Fields here
/// are the operationally important ones (the ones that change which
/// activation the operator is in the middle of); everything else is
/// reconciled via CloudKit.
public struct RemoteSessionState: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        status: String,
        myCallsign: String,
        startedAt: Date,
        endedAt: Date? = nil,
        mode: String,
        frequencyHz: UInt64? = nil,
        programs: [String] = [],
        activationType: String,
        parkReference: String? = nil,
        sotaReference: String? = nil,
        wwffReference: String? = nil,
        myGrid: String? = nil,
        stationCallsign: String? = nil,
        qsoCount: Int = 0,
        contestId: String? = nil
    ) {
        self.id = id
        self.status = status
        self.myCallsign = myCallsign
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.mode = mode
        self.frequencyHz = frequencyHz
        self.programs = programs
        self.activationType = activationType
        self.parkReference = parkReference
        self.sotaReference = sotaReference
        self.wwffReference = wwffReference
        self.myGrid = myGrid
        self.stationCallsign = stationCallsign
        self.qsoCount = qsoCount
        self.contestId = contestId
    }

    // MARK: Public

    public let id: UUID
    /// Mirrors `LoggingSessionStatus.rawValue`: `"active"`, `"paused"`, `"completed"`.
    public let status: String
    public let myCallsign: String
    public let startedAt: Date
    public let endedAt: Date?
    public let mode: String
    public let frequencyHz: UInt64?
    public let programs: [String]
    /// Mirrors `ActivationType.rawValue`.
    public let activationType: String
    public let parkReference: String?
    public let sotaReference: String?
    public let wwffReference: String?
    public let myGrid: String?
    public let stationCallsign: String?
    public let qsoCount: Int
    public let contestId: String?
}

// MARK: - ActiveSessionEvent

/// Emitted on the `activeSession` topic whenever the sender's local
/// "active session" pointer changes. Receivers apply via the
/// most-recent-startedAt rule.
public struct ActiveSessionEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(session: RemoteSessionState?, timestamp: Date = Date()) {
        self.session = session
        self.timestamp = timestamp
    }

    // MARK: Public

    /// `nil` indicates the sender currently has no active session.
    public let session: RemoteSessionState?
    public let timestamp: Date
}

// MARK: - SetActiveSessionCommand

/// Field → Sweep (or vice versa). Tells the receiver to adopt the
/// supplied session state as its active session. The receiver still
/// applies the most-recent-startedAt rule, so the command is a hint
/// rather than a force.
public struct SetActiveSessionCommand: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(requestID: UUID = UUID(), session: RemoteSessionState) {
        self.requestID = requestID
        self.session = session
    }

    // MARK: Public

    public let requestID: UUID
    public let session: RemoteSessionState
}
