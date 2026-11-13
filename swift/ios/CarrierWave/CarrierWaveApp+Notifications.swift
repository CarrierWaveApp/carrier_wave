import UIKit

// MARK: - App-wide Notification Names

extension Notification.Name {
    /// Posted by `ClubsSyncService` after a sync changed the club roster
    /// cache (new members, departures, or new clubs). Consumers that bake
    /// club membership into stored data — the session brag sheet's
    /// `sessionClubMembers` — recompute on this.
    static let clubMembershipDidChange = Notification.Name("clubMembershipDidChange")
    static let didReceiveADIFFile = Notification.Name("didReceiveADIFFile")
    static let didReceiveQSYSpot = Notification.Name("didReceiveQSYSpot")
    static let didReceiveQSYTune = Notification.Name("didReceiveQSYTune")
    static let didReceiveQSYLookup = Notification.Name(
        "didReceiveQSYLookup"
    )
    static let didReceiveQSYLog = Notification.Name("didReceiveQSYLog")
    static let didReceiveFriendInvite = Notification.Name(
        "didReceiveFriendInvite"
    )
    static let didReceiveWidgetDeepLink = Notification.Name(
        "didReceiveWidgetDeepLink"
    )
    /// Posted when the Phase 5 OAuth magic-link return (universal link or
    /// `carrierwave://auth?code=`) successfully exchanged the code for tokens.
    /// The verify view observes it to stop polling and show success.
    static let didCompleteOAuthVerification = Notification.Name(
        "didCompleteOAuthVerification"
    )
    /// Posted when an OAuth magic-link return arrived but the exchange failed
    /// (e.g. no pending verification on this device, or an expired link).
    static let didFailOAuthVerification = Notification.Name(
        "didFailOAuthVerification"
    )
    /// Posted when the Hunt widget tap (or another deep link) wants the
    /// Sessions tab to push directly into the Hunter Log (ActivityLogView).
    /// Falls back to showing the Hunter Log setup sheet when no log exists.
    static let didRequestHunterLog = Notification.Name(
        "didRequestHunterLog"
    )
    /// Posted when Home's hero Resume row wants the Sessions tab to actually
    /// reopen the open session (resume it if paused) rather than landing on
    /// the idle intent screen.
    static let didRequestResumeSession = Notification.Name(
        "didRequestResumeSession"
    )
    static let didDetectActivities = Notification.Name("didDetectActivities")
    static let didClearQSOs = Notification.Name("didClearQSOs")
    static let didReceiveWatchStartSession = Notification.Name(
        "didReceiveWatchStartSession"
    )
    static let didRestoreFromBackup = Notification.Name(
        "didRestoreFromBackup"
    )
    static let didStartSessionExternally = Notification.Name(
        "didStartSessionExternally"
    )
    /// Posted by `PebbleBridgeService` when the Pebble companion presses
    /// SELECT on the session screen. The active LoggerView observes it and
    /// treats the press as a remote "Enter" on whatever the user has typed.
    /// UserInfo: `rstSent`, `rstReceived` (both String, optional).
    static let didReceivePebbleLogQSO = Notification.Name(
        "didReceivePebbleLogQSO"
    )
    /// Posted when a spot is tapped on the On Air Now card/sheet to open
    /// the Hunter Log with the spot prefilled. UserInfo keys: callsign,
    /// frequencyMHz, mode, ref, comment (all optional except callsign).
    static let didSelectHunterSpot = Notification.Name(
        "didSelectHunterSpot"
    )
    /// Posted after the dashboard stats pipeline finishes its initial
    /// full-table scans. Deferred services (CloudSync) listen for this
    /// to avoid concurrent scans that trigger watchdog kills.
    nonisolated static let statsPipelineComplete = Notification.Name(
        "statsPipelineComplete"
    )
    /// Posted when the user taps a satellite pass-alert notification.
    /// UserInfo carries the pass geometry (`noradID`, `satelliteName`,
    /// `aos`, `los`, `peakElevationDeg`, …) so the satellites tab can select
    /// the bird and start the pass-countdown Live Activity.
    static let didReceiveSatellitePassAlert = Notification.Name(
        "didReceiveSatellitePassAlert"
    )
    /// Posted by `SolarPollingService` after it persists a new
    /// `SolarSnapshot` (at most every 30 minutes due to the dedup window).
    /// Listeners refresh their cached "latest snapshot" — this replaces a
    /// `@Query` dependency that was invalidating the dashboard `OnAirCard`
    /// on every container save and tanking scroll performance.
    nonisolated static let didStoreSolarSnapshot = Notification.Name(
        "didStoreSolarSnapshot"
    )
}
