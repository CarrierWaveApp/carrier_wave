import CarrierWaveCore
import Foundation

// LAN-side handlers for the `activeSession` topic. Kept in a separate
// extension file so the actor body in `RemoteOpConnection` stays
// under the SwiftLint type-body cap.

extension RemoteOpConnection {
    /// Apply an inbound `commandSetActiveSession` from a paired
    /// device. Service runs on `@MainActor`; we hop and ack on
    /// completion.
    func handleSetActiveSession(_ cmd: SetActiveSessionCommand) async {
        guard await requireAuth(action: "set-active-session"), let service else {
            return
        }
        let ack = await MainActor.run {
            service.handleSetActiveSession(cmd)
        }
        await sendFrame(.ack(ack))
    }

    /// Send the current active-session snapshot in response to a
    /// `subscribe(activeSession)` frame. Nil session is sent as an
    /// `eventActiveSession` with `session == nil` so the receiver
    /// can clear its mirror cleanly.
    func sendCurrentActiveSession() async {
        guard let service else {
            return
        }
        let snapshot = await MainActor.run {
            service.currentActiveSessionSnapshot()
        }
        await sendFrame(.eventActiveSession(snapshot))
    }
}
