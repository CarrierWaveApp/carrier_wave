import CarrierWaveCore
import Foundation

//
// CW keyer command handlers split off the main RemoteOpConnection actor body
// to keep that type under SwiftLint's 300-line type-body cap. Same-file
// extensions on actors retain access to private members; this lives in its
// own file so the per-handler footprint stays readable.

extension RemoteOpConnection {
    func handleSendCW(_ cmd: SendCWCommand) async {
        guard await requireAuth(action: "send CW"), let service else {
            return
        }
        let ack = await service.handleSendCW(cmd)
        await sendFrame(.ack(ack))
    }

    func handleStopCW(_ cmd: StopCWCommand) async {
        guard await requireAuth(action: "stop CW"), let service else {
            return
        }
        let ack = await service.handleStopCW(cmd)
        await sendFrame(.ack(ack))
    }

    func handleSetCWSpeed(_ cmd: SetCWSpeedCommand) async {
        guard await requireAuth(action: "set CW speed"), let service else {
            return
        }
        let ack = await service.handleSetCWSpeed(cmd)
        await sendFrame(.ack(ack))
    }

    func handlePlayCWSlot(_ cmd: PlayCWSlotCommand) async {
        guard await requireAuth(action: "play CW slot"), let service else {
            return
        }
        let ack = await service.handlePlayCWSlot(cmd)
        await sendFrame(.ack(ack))
    }

    func handleSetCWSlot(_ cmd: SetCWSlotCommand) async {
        guard await requireAuth(action: "program CW slot"), let service else {
            return
        }
        let ack = await service.handleSetCWSlot(cmd)
        await sendFrame(.ack(ack))
    }

    func sendCurrentCWStatus() async {
        guard let service else {
            return
        }
        let snapshot = await MainActor.run { service.currentCWStatusSnapshot() }
        if let snapshot {
            await sendFrame(.eventCWStatus(snapshot))
        }
    }

    func sendCurrentCWSlots() async {
        guard let service else {
            return
        }
        let snapshot = await service.currentCWSlotsSnapshot()
        if let snapshot {
            await sendFrame(.eventCWSlots(snapshot))
        }
    }

    /// Returns true if the connection is authenticated; otherwise sends a
    /// `notAuthenticated` error frame and returns false.
    func requireAuth(action: String) async -> Bool {
        if authenticated {
            return true
        }
        await sendFrame(.errorFrame(.init(
            code: .notAuthenticated,
            message: "\(action) before pairing"
        )))
        return false
    }
}
