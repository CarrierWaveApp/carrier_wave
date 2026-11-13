import CarrierWaveCore
import Foundation

// Converts between the wire-format `RemoteSessionState` (defined in
// CarrierWaveCore so the protocol layer stays free of SwiftData) and
// `LoggingSession` / `LoggingSessionFields`. Used by both Field and
// Sweep on the LAN auto-continuity path so receivers can materialize a
// remote-active session into their local SwiftData store.

public extension RemoteSessionState {
    /// Build a wire snapshot from a SwiftData `LoggingSession`. Read on
    /// the main actor; do not pass the resulting struct back to a
    /// SwiftData context — it's `Sendable` precisely so it can cross
    /// boundaries safely.
    @MainActor
    init(session: LoggingSession) {
        let frequencyHz: UInt64? = {
            guard let freqMHz = session.frequency, freqMHz > 0 else {
                return nil
            }
            return UInt64((freqMHz * 1_000_000).rounded())
        }()
        self.init(
            id: session.id,
            status: session.statusRawValue,
            myCallsign: session.myCallsign,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            mode: session.mode,
            frequencyHz: frequencyHz,
            programs: session.programs.sorted(),
            activationType: session.activationTypeRawValue,
            parkReference: session.parkReference,
            sotaReference: session.sotaReference,
            wwffReference: session.wwffReference,
            myGrid: session.myGrid,
            stationCallsign: session.stationCallsign,
            qsoCount: session.qsoCount,
            contestId: session.contestId
        )
    }
}

public extension LoggingSession {
    /// Apply an inbound LAN snapshot to an existing session. Caller is
    /// responsible for fetching the matching record by `id` first;
    /// this method does not insert.
    ///
    /// IMPORTANT — once a session has been ended locally, that's terminal.
    /// We refuse to overwrite `status`/`endedAt` from a remote snapshot that
    /// claims the session is still active. CW Sweep / another peer can hold
    /// stale state for many seconds (or until restart), and replaying it
    /// onto the just-ended local record would resurrect the session and
    /// re-adopt it on the next continuity tick. The user's deliberate
    /// end-session action must always win against remote noise.
    @MainActor
    func apply(remote: RemoteSessionState) {
        let localIsEnded = endedAt != nil || statusRawValue == "completed"
        let remoteWantsActive = remote.status == "active" && remote.endedAt == nil
        if !(localIsEnded && remoteWantsActive) {
            statusRawValue = remote.status
            endedAt = remote.endedAt
        }
        myCallsign = remote.myCallsign
        startedAt = remote.startedAt
        mode = remote.mode
        if let hz = remote.frequencyHz {
            frequency = Double(hz) / 1_000_000
        } else {
            frequency = nil
        }
        if !remote.programs.isEmpty {
            programs = Set(remote.programs)
        }
        activationTypeRawValue = remote.activationType
        parkReference = remote.parkReference
        sotaReference = remote.sotaReference
        wwffReference = remote.wwffReference
        myGrid = remote.myGrid
        stationCallsign = remote.stationCallsign
        qsoCount = remote.qsoCount
        contestId = remote.contestId
    }

    /// Build a fresh SwiftData session from a LAN snapshot. Used when
    /// the receiving side has never heard of this session UUID before.
    @MainActor
    static func makeFromRemote(_ remote: RemoteSessionState) -> LoggingSession {
        let session = LoggingSession(
            id: remote.id,
            myCallsign: remote.myCallsign,
            startedAt: remote.startedAt,
            frequency: remote.frequencyHz.map { Double($0) / 1_000_000 },
            mode: remote.mode,
            programs: Set(remote.programs),
            activationType: ActivationType(rawValue: remote.activationType) ?? .casual,
            parkReference: remote.parkReference,
            sotaReference: remote.sotaReference,
            wwffReference: remote.wwffReference,
            myGrid: remote.myGrid,
            contestId: remote.contestId,
            stationCallsign: remote.stationCallsign
        )
        session.statusRawValue = remote.status
        session.endedAt = remote.endedAt
        session.qsoCount = remote.qsoCount
        return session
    }
}
