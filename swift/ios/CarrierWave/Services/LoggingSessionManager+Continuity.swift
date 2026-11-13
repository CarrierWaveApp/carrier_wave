import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData
import UIKit

// Auto-continuity: when CloudKit (or, later, the LAN RemoteOp link)
// surfaces a remote LoggingSession that should be the active one on
// this device, swap to it without requiring a button press. The rule
// is "most recent startedAt wins" — applied identically on both
// platforms so they converge.

extension LoggingSessionManager {
    /// Begin observing CloudKit / LAN active-session change notifications.
    /// Idempotent — call once after init from the owning view (or app).
    func startContinuityObservation() {
        guard !continuityObserverInstalled else {
            return
        }
        continuityObserverInstalled = true
        let center = NotificationCenter.default
        center.addObserver(
            forName: .cwLoggingSessionRemotelyChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let touched = (note.userInfo?[
                SessionContinuityUserInfoKey.affectedSessionIDsKey
            ] as? [UUID]) ?? []
            Task { @MainActor [weak self] in
                self?.applyRemoteSessionChange(affectedIDs: touched)
            }
        }
        center.addObserver(
            forName: .cwActiveSessionShouldChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let id = note.userInfo?[
                SessionContinuityUserInfoKey.activeSessionIDKey
            ] as? UUID
            Task { @MainActor [weak self] in
                self?.applyActiveSessionShouldChange(id: id)
            }
        }
        center.addObserver(
            forName: .cwLANActiveSessionReceived,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let snapshot = note.userInfo?["snapshot"] as? RemoteSessionState
            Task { @MainActor [weak self] in
                self?.applyLANSnapshot(snapshot)
            }
        }
        // Re-arming observation of our own `activeSession` pointer so
        // a single notification fires every time it changes — picks
        // up start/pause/resume/end without instrumenting each call
        // site individually.
        observeLocalActiveSession()
    }

    /// Re-arming `withObservationTracking` watcher that fires
    /// `cwLocalActiveSessionChanged` whenever `activeSession` changes,
    /// so peers (currently `RemoteSweepCoordinator`) can mirror it
    /// over the LAN. Re-installs itself on every change to keep the
    /// observation alive across mutations.
    private func observeLocalActiveSession() {
        let session: LoggingSession? = withObservationTracking {
            activeSession
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeLocalActiveSession()
            }
        }
        // Only fire when the identity changed — payload-only changes
        // ride the CloudKit channel and the periodic Sweep refresh.
        if lastBroadcastSessionID == session?.id {
            return
        }
        lastBroadcastSessionID = session?.id
        var userInfo: [AnyHashable: Any] = [
            SessionContinuityUserInfoKey.originKey: SessionContinuityOrigin.local.rawValue,
        ]
        if let session {
            let snapshot = RemoteSessionState(session: session)
            userInfo[SessionContinuityUserInfoKey.activeSessionIDKey] = snapshot.id
            userInfo["snapshot"] = snapshot
        }
        NotificationCenter.default.post(
            name: .cwLocalActiveSessionChanged,
            object: nil,
            userInfo: userInfo
        )
    }

    private func applyLANSnapshot(_ snapshot: RemoteSessionState?) {
        guard let snapshot else {
            return
        }
        let id = snapshot.id
        var desc = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == id }
        )
        desc.fetchLimit = 1
        let session: LoggingSession
        if let existing = try? modelContext.fetch(desc).first {
            existing.apply(remote: snapshot)
            session = existing
        } else {
            let inserted = LoggingSession.makeFromRemote(snapshot)
            modelContext.insert(inserted)
            session = inserted
        }
        try? EntityWriteSink.commitUpsert(session, in: modelContext)
        // Re-use the CloudKit-path adoption flow; `should-change`
        // listener already runs the most-recent-startedAt rule.
        NotificationCenter.default.post(
            name: .cwActiveSessionShouldChange,
            object: nil,
            userInfo: [
                SessionContinuityUserInfoKey.activeSessionIDKey: id,
                SessionContinuityUserInfoKey.originKey: SessionContinuityOrigin.lan.rawValue,
            ]
        )
    }

    private func applyRemoteSessionChange(affectedIDs: [UUID]) {
        // Re-resolve "the active session" from SwiftData: most-recently-
        // startedAt session whose status is .active. If it differs from
        // our current activeSession, adopt it.
        guard let winner = mostRecentlyStartedActiveSession() else {
            // No remote-active session and no local-active session.
            // If we still hold one in-memory whose status flipped to
            // paused/completed remotely, drop it.
            if let current = activeSession,
               affectedIDs.contains(current.id),
               !current.isActive
            {
                releaseActiveSession()
            }
            return
        }
        // CAR — don't resurrect a session the user just ended locally.
        // CloudKit echoes / LAN snapshots can land seconds after `endSession`
        // with stale `.active` state and silently re-adopt the just-ended
        // session, defeating the explicit user action.
        if SessionContinuityState.shared.recentlyEnded(winner.id) {
            return
        }
        if let current = activeSession, current.id == winner.id {
            // Same session — fields may have changed but identity
            // didn't. SwiftData re-render handles updates.
            return
        }
        adopt(winner)
    }

    private func applyActiveSessionShouldChange(id: UUID?) {
        guard let id else {
            return
        }
        // In-memory grace window — short-circuits CloudKit/LAN echoes that
        // land seconds after `endSession()` within the same process.
        if SessionContinuityState.shared.recentlyEnded(id) {
            return
        }
        var desc = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == id }
        )
        desc.fetchLimit = 1
        guard let session = try? modelContext.fetch(desc).first else {
            return
        }
        // Never resurrect a session the user has explicitly ended. The
        // in-memory `recentlyEnded` window is wiped on app relaunch, so a
        // stale CloudKit echo / LAN snapshot from another device would
        // otherwise flip `.completed` back to `.active` and re-adopt it
        // the next time SessionsTabView checks `hasActiveSession`.
        // The persisted `endedAt`/`status` IS the user's last word.
        if session.endedAt != nil || session.status == .completed {
            return
        }
        if session.status != .active {
            session.status = .active
            session.cloudDirtyFlag = true
        }
        if let current = activeSession, current.id == session.id {
            return
        }
        adopt(session)
    }

    /// Pause the local active session (if any) and adopt the supplied
    /// session as the new active one, running the full lifecycle so
    /// Live Activity, GPS, radio, auto-spot, etc. all reflect it.
    private func adopt(_ session: LoggingSession) {
        var touchedSessions: [LoggingSession] = [session]
        if let current = activeSession, current.id != session.id {
            // Pause without ending — user can resume the prior session
            // later from the sessions list.
            current.status = .paused
            current.cloudDirtyFlag = true
            touchedSessions.append(current)
        }
        activeSession = session
        UserDefaults.standard.set(
            session.id.uuidString, forKey: activeSessionIdKey
        )
        // Both the adopted and the paused session ride one coordinated seam write
        // (over-staging an unchanged session is an idempotent cw-store upsert;
        // under-staging would drop it in `.on` mode). The continuity handlers only
        // mutate LoggingSessions before this save.
        try? EntityWriteSink.commitUpsert(touchedSessions, in: modelContext)

        cacheServiceConfiguration()
        if keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        startAutoSpotTimer()
        startUTCMidnightTimer()
        startSpotCommentsPolling()
        startSpotMonitoring()
        connectRadio()
        startGridObservation()
        if !liveActivityService.reconnect() {
            startLiveActivity()
        }
        locationService.start()
    }

    private func releaseActiveSession() {
        activeSession = nil
        UserDefaults.standard.removeObject(forKey: activeSessionIdKey)
        clearSelfSpotFrequency()
        liveActivityService.cleanupStale()
    }

    private func mostRecentlyStartedActiveSession() -> LoggingSession? {
        // SwiftData predicates can't compare optional dates against nil with
        // the same fluency as `endedAt == nil`, so filter post-fetch. The
        // `endedAt` check defends against corrupt rows where status is
        // `.active` but `endedAt` is set (a state past resurrections could
        // produce). The user's explicit "end" must always win.
        var desc = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "active" },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        desc.fetchLimit = 10
        guard let sessions = try? modelContext.fetch(desc) else {
            return nil
        }
        var seen: Set<UUID> = []
        for session in sessions where session.endedAt == nil {
            guard seen.insert(session.id).inserted else {
                continue
            }
            return session
        }
        return nil
    }

    private var continuityObserverInstalled: Bool {
        get { ContinuityState.shared.installed[ObjectIdentifier(self)] ?? false }
        set { ContinuityState.shared.installed[ObjectIdentifier(self)] = newValue }
    }

    private var lastBroadcastSessionID: UUID? {
        get { ContinuityState.shared.lastBroadcastID[ObjectIdentifier(self)] }
        set { ContinuityState.shared.lastBroadcastID[ObjectIdentifier(self)] = newValue }
    }
}

// MARK: - ContinuityState

// Swift extensions can't add stored properties, so we side-table per-
// manager state. The manager is `@MainActor`, so accessing these
// dictionaries is safe without locking.

@MainActor
private final class ContinuityState {
    static let shared = ContinuityState()

    var installed: [ObjectIdentifier: Bool] = [:]
    var lastBroadcastID: [ObjectIdentifier: UUID] = [:]
}
