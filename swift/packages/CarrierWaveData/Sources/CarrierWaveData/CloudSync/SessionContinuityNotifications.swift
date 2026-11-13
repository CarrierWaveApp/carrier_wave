import Foundation

// Cross-device "active session" continuity. Both Carrier Wave (iOS) and
// CW Sweep (macOS) post these notifications when LoggingSession state
// changes inbound from CloudKit (or, later, the LAN RemoteOp link) so
// each app can adopt the remote-active session without the user having
// to press a sync / connect button.

public extension Notification.Name {
    /// Fired after CloudSyncJournalEngine applies one or more
    /// LoggingSession upserts. Listeners should re-resolve "the
    /// active session" — typically the most-recently-startedAt
    /// session whose status is `.active`. UserInfo carries the
    /// affected session UUIDs under `affectedSessionIDsKey`.
    static let cwLoggingSessionRemotelyChanged = Notification.Name(
        "com.jsvana.CarrierWave.loggingSessionRemotelyChanged"
    )

    /// Fired when this device's "active session" pointer should
    /// switch to a different LoggingSession (e.g. because another
    /// device just started an activation). UserInfo carries the new
    /// active session UUID under `activeSessionIDKey`.
    static let cwActiveSessionShouldChange = Notification.Name(
        "com.jsvana.CarrierWave.activeSessionShouldChange"
    )

    /// Fired by `RemoteSweepCoordinator` when a `RemoteSessionState`
    /// snapshot arrives over the LAN `activeSession` topic. Listeners
    /// (typically `LoggingSessionManager`) materialize the snapshot
    /// into SwiftData and re-evaluate adoption. UserInfo carries the
    /// `RemoteSessionState` under the `"snapshot"` key.
    static let cwLANActiveSessionReceived = Notification.Name(
        "com.jsvana.CarrierWave.lanActiveSessionReceived"
    )

    /// Fired whenever this device's local `LoggingSessionManager`
    /// changes its `activeSession` pointer. Listeners (typically
    /// `RemoteSweepCoordinator`) push the new state over the LAN
    /// when connected to a remote peer. UserInfo may carry a
    /// `RemoteSessionState` under the `"snapshot"` key when the new
    /// active session is non-nil.
    static let cwLocalActiveSessionChanged = Notification.Name(
        "com.jsvana.CarrierWave.localActiveSessionChanged"
    )
}

// MARK: - SessionContinuityUserInfoKey

public enum SessionContinuityUserInfoKey {
    /// `[UUID]` — sessions touched by the most recent inbound batch.
    public static let affectedSessionIDsKey = "affectedSessionIDs"
    /// `UUID` — session that should become this device's active session.
    public static let activeSessionIDKey = "activeSessionID"
    /// `String` — origin of the change, e.g. `"cloudkit"` or `"lan"`.
    public static let originKey = "origin"
}

// MARK: - SessionContinuityOrigin

public enum SessionContinuityOrigin: String {
    case cloudkit
    case lan
    case local
}
