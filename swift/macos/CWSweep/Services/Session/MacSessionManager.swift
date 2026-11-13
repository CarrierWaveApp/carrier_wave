import CarrierWaveData
import Foundation
import SwiftData
import SwiftUI

// MARK: - MacSessionManager

/// macOS-side session lifecycle service. Slim sibling of iOS
/// `LoggingSessionManager` — implements the cross-platform
/// `SessionLifecycleAPI` contract from CarrierWaveData and provides the
/// macOS-specific `startSession` that the Sessions landing intents call.
///
/// Scope: lifecycle + persistence only. iOS-style side effects (Live Activity,
/// POTA spot polling, WebSDR auto-start, TOTA GPS tracking) don't apply on
/// macOS; the contester operating UI is driven by `ContestManager` and
/// `CustomLayoutView` separately.
///
/// All state lives in SwiftData. After every mutation a `Notification.Name
/// .didChangeLoggingSession` is posted so the Sessions landing
/// (`SessionsSidebarRoot`) refreshes its FetchDescriptor-backed lists.
@MainActor
@Observable
public final class MacSessionManager: SessionLifecycleAPI {
    // MARK: Lifecycle

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    // MARK: Public

    public private(set) var activeSession: LoggingSession?
    public private(set) var pausedSessions: [LoggingSession] = []

    /// Start a new session and make it the active one. Pauses any existing
    /// active session first so the multi-session invariant (single primary
    /// active, N paused) holds.
    @discardableResult
    public func startSession(
        myCallsign: String,
        mode: String = "CW",
        frequency: Double? = nil,
        activationType: ActivationType = .casual,
        programs: Set<String> = [],
        parkReference: String? = nil,
        sotaReference: String? = nil,
        wwffReference: String? = nil,
        myGrid: String? = nil,
        power: Int? = nil,
        contestId: String? = nil,
        contestCategory: String? = nil,
        contestOverlayCategory: String? = nil,
        contestPower: String? = nil,
        contestBands: String? = nil
    ) -> LoggingSession {
        if activeSession != nil {
            pauseSession()
        }
        let session = LoggingSession(
            myCallsign: myCallsign.uppercased(),
            startedAt: Date(),
            frequency: frequency,
            mode: mode,
            programs: programs,
            activationType: activationType,
            parkReference: parkReference,
            sotaReference: sotaReference,
            wwffReference: wwffReference,
            myGrid: myGrid?.uppercased(),
            power: power,
            contestId: contestId,
            contestCategory: contestCategory,
            contestOverlayCategory: contestOverlayCategory,
            contestPower: contestPower,
            contestBands: contestBands
        )
        session.cloudDirtyFlag = true
        modelContext.insert(session)
        try? CwStoreSeams.save(modelContext, sessions: [session])
        activeSession = session
        postChange()
        return session
    }

    /// Convenience: silent Casual session for the auto-Casual-on-first-QSO
    /// flow in `ParsedEntryView`. `myCallsign` should be the operator's
    /// configured station callsign at the time of the QSO.
    @discardableResult
    public func startCasualSession(myCallsign: String, mode: String = "CW") -> LoggingSession {
        startSession(myCallsign: myCallsign, mode: mode, activationType: .casual)
    }

    public func pauseSession() {
        guard let session = activeSession else {
            return
        }
        session.pause()
        session.cloudDirtyFlag = true
        try? CwStoreSeams.save(modelContext, sessions: [session])
        activeSession = nil
        postChange()
    }

    public func resumeSession(_ session: LoggingSession) {
        if let existing = activeSession, existing.id != session.id {
            pauseSession()
        }
        session.resume()
        session.cloudDirtyFlag = true
        try? CwStoreSeams.save(modelContext, sessions: [session])
        activeSession = session
        postChange()
    }

    public func finishSession(_ session: LoggingSession) {
        session.end()
        session.cloudDirtyFlag = true
        if activeSession?.id == session.id {
            activeSession = nil
        }
        try? CwStoreSeams.save(modelContext, sessions: [session])
        postChange()
    }

    /// Re-read active + paused sessions from SwiftData. Called from
    /// `SessionsSidebarRoot.task` on appear and after every notification.
    public func refresh() {
        activeSession = fetchActiveSession()
        pausedSessions = fetchPausedSessions()
    }

    // MARK: Private

    private let modelContext: ModelContext

    private func fetchActiveSession() -> LoggingSession? {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "active" },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        guard let sessions = try? modelContext.fetch(descriptor) else {
            return nil
        }
        var seen = Set<UUID>()
        for session in sessions where seen.insert(session.id).inserted {
            return session
        }
        return nil
    }

    private func fetchPausedSessions() -> [LoggingSession] {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "paused" },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        guard let sessions = try? modelContext.fetch(descriptor) else {
            return []
        }
        var seen = Set<UUID>()
        return sessions.filter { seen.insert($0.id).inserted }
    }

    private func postChange() {
        NotificationCenter.default.post(name: .didChangeLoggingSession, object: nil)
    }
}
