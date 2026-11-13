import CarrierWaveCore
import UIKit

// MARK: - Satellite Doppler Commands (CW Sat Bridge)

/// Schedule-upload and pass-control commands for the CW Sat Bridge. Split
/// from `BridgeProtocol` to keep that file focused; relies on its
/// `internal` `rawTransport` / ack-continuation members.
extension BridgeProtocol {
    /// Send a SatScheduleBegin and await the bridge's ack (nil = timeout /
    /// not framed / send failure). Upload is stop-and-wait per frame.
    func sendSatBegin(_ header: BridgeFrame.SatScheduleHeader) async -> Cwbp_SatScheduleAck? {
        await sendSatFrameAwaitingAck(BridgeFrame.buildSatBegin(header))
    }

    /// Send one packed step chunk and await its ack.
    func sendSatChunk(scheduleID: UInt32, seq: UInt32, steps: Data) async -> Cwbp_SatScheduleAck? {
        await sendSatFrameAwaitingAck(
            BridgeFrame.buildSatChunk(scheduleID: scheduleID, seq: seq, steps: steps)
        )
    }

    /// Arm the uploaded schedule. Status arrives via `.satStatus` events.
    func sendSatStart(scheduleID: UInt32, aosInMs: UInt64, elapsedMs: UInt64) async throws {
        guard mode == .framed else {
            return
        }
        try await rawTransport.send(
            BridgeFrame.buildSatStart(scheduleID: scheduleID, aosInMs: aosInMs, elapsedMs: elapsedMs)
        )
    }

    /// Cancel the armed/running pass.
    func sendSatAbort() async throws {
        guard mode == .framed else {
            return
        }
        try await rawTransport.send(BridgeFrame.buildSatAbort())
    }

    /// Flip the radio's active VFO between downlink (A) and uplink (B).
    func sendSatSetVfo(uplink: Bool) async throws {
        guard mode == .framed else {
            return
        }
        try await rawTransport.send(BridgeFrame.buildSatSetVfo(uplink: uplink))
    }

    func failPendingSatAck() {
        pendingSatAckContinuation?.resume(returning: nil)
        pendingSatAckContinuation = nil
        satAckTimeoutTask?.cancel()
        satAckTimeoutTask = nil
    }

    private func sendSatFrameAwaitingAck(_ frame: Data) async -> Cwbp_SatScheduleAck? {
        guard mode == .framed else {
            return nil
        }
        // Cancel any stale pending ack wait.
        failPendingSatAck()

        // Arm the continuation BEFORE sending: the sat bridge acks a Begin/
        // chunk within microseconds of the write, so the notification can
        // arrive while `rawTransport.send` is still suspended — installing
        // the continuation afterwards (the sendSetVerify pattern, where the
        // radio round-trip masks the race) loses the ack and times out.
        return await withCheckedContinuation { continuation in
            pendingSatAckContinuation = continuation
            satAckTimeoutTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else {
                    return
                }
                Task { @MainActor in
                    RadioService.shared.addLog(.error, "Sat TX: ack timeout (5s)")
                }
                failPendingSatAck()
            }
            Task {
                do {
                    try await rawTransport.send(frame)
                } catch {
                    Task { @MainActor in
                        RadioService.shared.addLog(
                            .error,
                            "Sat TX: send failed — \(error.localizedDescription)"
                        )
                    }
                    failPendingSatAck()
                }
            }
        }
    }
}
