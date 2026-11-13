import CarrierWaveCore
import CarrierWaveData
import Foundation

// LAN-side active-session continuity. Inbound `eventActiveSession`
// frames from Sweep are forwarded as a `cwLANActiveSessionReceived`
// notification (so `LoggingSessionManager` can materialize and
// adopt). Outbound: when our local manager fires
// `cwLocalActiveSessionChanged` we push the snapshot up to Sweep so
// it can mirror without waiting for CloudKit.

extension RemoteSweepCoordinator {
    /// Applied when Sweep pushes its current active LoggingSession.
    /// Forwards the snapshot to `LoggingSessionManager` via a
    /// notification — the manager owns the SwiftData context and
    /// runs the same adoption logic as the CloudKit path.
    func handleRemoteActiveSession(_ event: ActiveSessionEvent) {
        remoteActiveSession = event.session
        guard let state = event.session else {
            return
        }
        NotificationCenter.default.post(
            name: .cwLANActiveSessionReceived,
            object: nil,
            userInfo: [
                SessionContinuityUserInfoKey.activeSessionIDKey: state.id,
                "snapshot": state,
                SessionContinuityUserInfoKey.originKey: SessionContinuityOrigin.lan.rawValue,
            ]
        )
    }

    /// Listen for `cwLocalActiveSessionChanged` posted by
    /// `LoggingSessionManager` whenever the operator's active
    /// LoggingSession changes. Forwards the snapshot to Sweep over
    /// the LAN if connected; otherwise stashes it for the next
    /// successful subscribe.
    func registerLocalSessionObserver() {
        NotificationCenter.default.addObserver(
            forName: .cwLocalActiveSessionChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Extract the Sendable payload before hopping actors —
            // Notification itself is not Sendable.
            let snapshot = note.userInfo?["snapshot"] as? RemoteSessionState
            Task { @MainActor [weak self] in
                self?.applyLocalSessionSnapshot(snapshot)
            }
        }
    }

    private func applyLocalSessionSnapshot(_ snapshot: RemoteSessionState?) {
        pendingLocalSessionPush = snapshot
        guard let snapshot, let client else {
            return
        }
        if connectionState != .connected {
            return
        }
        Task { [weak self] in
            do {
                _ = try await client.setActiveSession(snapshot)
            } catch {
                await MainActor.run {
                    self?.recordError("push session: \(error.localizedDescription)")
                }
            }
        }
    }
}
