import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog
import SwiftData

private let sessionLogger = Logger(subsystem: "com.jsvana.CWSweep", category: "RemoteOpSession")

// LAN-side support for the `activeSession` RemoteOp topic. Sweep sends
// a snapshot whenever its local active session changes, and applies
// `commandSetActiveSession` frames sent by Field by repeating the
// CloudKit conflict rule (most-recent-startedAt wins). The `Continuity`
// notification path on `CarrierWaveData` is the same one CloudKit
// reactivity uses, so the local UI updates without any extra wiring.

@MainActor
extension RemoteOpService {
    /// Snapshot of Sweep's currently-active LoggingSession, suitable
    /// for sending on the `activeSession` topic. Nil when no session
    /// is active.
    func currentActiveSessionSnapshot() -> ActiveSessionEvent {
        let state = fetchActiveSessionState()
        return ActiveSessionEvent(session: state, timestamp: Date())
    }

    /// Broadcast the current active-session snapshot to every
    /// authenticated client subscribed to `activeSession`.
    func broadcastActiveSession() {
        broadcast(.eventActiveSession(currentActiveSessionSnapshot()), topic: .activeSession)
    }

    /// Handle a `commandSetActiveSession` frame from Field. Materializes
    /// the session into SwiftData (insert or update by UUID), then posts
    /// `cwActiveSessionShouldChange` so the Sweep UI swaps over without
    /// further round-tripping.
    func handleSetActiveSession(_ command: SetActiveSessionCommand) -> Ack {
        guard let container = modelContainer else {
            return Ack(
                requestID: command.requestID,
                success: false,
                detail: "model container unavailable"
            )
        }
        let context = ModelContext(container)
        let id = command.session.id
        var desc = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == id }
        )
        desc.fetchLimit = 1
        let session: LoggingSession
        if let existing = try? context.fetch(desc).first {
            existing.apply(remote: command.session)
            existing.cloudDirtyFlag = true
            session = existing
        } else {
            let new = LoggingSession.makeFromRemote(command.session)
            new.cloudDirtyFlag = true
            context.insert(new)
            session = new
        }
        do {
            try OffMainStoreSeam.commitLoggingSessions([session], in: context)
        } catch {
            sessionLogger.error(
                "Failed to apply remote session: \(error.localizedDescription)"
            )
            return Ack(
                requestID: command.requestID,
                success: false,
                detail: error.localizedDescription
            )
        }
        // Fan out to local listeners so views and the StatusBar reflect
        // the new active session immediately. Origin = lan so listeners
        // can disambiguate from CloudKit-driven changes.
        NotificationCenter.default.post(
            name: .cwActiveSessionShouldChange,
            object: nil,
            userInfo: [
                SessionContinuityUserInfoKey.activeSessionIDKey: session.id,
                SessionContinuityUserInfoKey.originKey: SessionContinuityOrigin.lan.rawValue,
            ]
        )
        return Ack(requestID: command.requestID, success: true)
    }

    private func fetchActiveSessionState() -> RemoteSessionState? {
        guard let container = modelContainer else {
            return nil
        }
        let context = ModelContext(container)
        var desc = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "active" },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        desc.fetchLimit = 10
        guard let sessions = try? context.fetch(desc) else {
            return nil
        }
        var seen: Set<UUID> = []
        for session in sessions {
            guard seen.insert(session.id).inserted else {
                continue
            }
            return RemoteSessionState(session: session)
        }
        return nil
    }
}

// MARK: - RemoteOpSessionBroadcaster

/// Bridges SwiftData / CloudKit notifications to the LAN
/// `activeSession` topic so subscribers see local Sweep changes
/// without polling. Owned by `SharedEnvironment` and started after
/// the model container is wired in.
@MainActor
final class RemoteOpSessionBroadcaster {
    // MARK: Lifecycle

    init(service: RemoteOpService) {
        self.service = service
    }

    deinit {
        // Block-based observers self-detach when the holder is
        // released; nothing to do here.
    }

    // MARK: Internal

    func start() {
        guard !started else {
            return
        }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .cwLoggingSessionRemotelyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.broadcastIfChanged()
            }
        })
        observers.append(center.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.broadcastIfChanged()
            }
        })
        // Send an initial snapshot once the broadcaster spins up so
        // any client that subscribed before the first save has fresh
        // state.
        broadcastIfChanged(force: true)
    }

    func stop() {
        started = false
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: Private

    private weak var service: RemoteOpService?
    private var started = false
    private var observers: [NSObjectProtocol] = []
    private var lastSnapshot: ActiveSessionEvent?

    private func broadcastIfChanged(force: Bool = false) {
        guard let service else {
            return
        }
        let event = service.currentActiveSessionSnapshot()
        if !force, let last = lastSnapshot, last.session == event.session {
            return
        }
        lastSnapshot = event
        service.broadcast(.eventActiveSession(event), topic: .activeSession)
    }
}
