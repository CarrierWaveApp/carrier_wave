import CarrierWaveCore
import UIKit

//
// CW keyer command sends split off the main RemoteSweepClient actor body to
// keep it under SwiftLint's 300-line type-body cap. Each call mints a request
// ID, posts the frame, and waits for the matching `Ack` (with the same 8s
// timeout the other commands use).

extension RemoteSweepClient {
    /// Send a CW string through Sweep's bridge keyer. Returns the server's ack.
    func sendCWText(_ text: String, radioID: String? = nil) async throws -> Ack {
        let id = UUID()
        let frame = RemoteOpFrame.commandSendCW(.init(requestID: id, text: text, radioID: radioID))
        try await sendFrame(frame)
        return try await awaitAck(for: id)
    }

    /// Stop any active CW transmission on Sweep's bridge keyer.
    func stopCW(radioID: String? = nil) async throws -> Ack {
        let id = UUID()
        let frame = RemoteOpFrame.commandStopCW(.init(requestID: id, radioID: radioID))
        try await sendFrame(frame)
        return try await awaitAck(for: id)
    }

    /// Set Sweep's bridge keyer speed in WPM. Sweep clamps to 5...60.
    func setCWSpeed(wpm: UInt8, radioID: String? = nil) async throws -> Ack {
        let id = UUID()
        let frame = RemoteOpFrame.commandSetCWSpeed(.init(requestID: id, wpm: wpm, radioID: radioID))
        try await sendFrame(frame)
        return try await awaitAck(for: id)
    }

    /// Play CW memory slot 1...8 with optional template substitution context.
    func playCWSlot(
        _ slot: UInt8,
        context: [String: String] = [:],
        radioID: String? = nil
    ) async throws -> Ack {
        let id = UUID()
        let frame = RemoteOpFrame.commandPlayCWSlot(.init(
            requestID: id,
            slot: slot,
            context: context,
            radioID: radioID
        ))
        try await sendFrame(frame)
        return try await awaitAck(for: id)
    }

    /// Program a CW memory slot on Sweep (1...8). Sweep persists the change
    /// and pushes it into the bridge's slot memory before acking.
    func setCWSlot(
        _ slot: UInt8,
        label: String,
        text: String,
        radioID: String? = nil
    ) async throws -> Ack {
        let id = UUID()
        let frame = RemoteOpFrame.commandSetCWSlot(.init(
            requestID: id,
            slot: slot,
            label: label,
            text: text,
            radioID: radioID
        ))
        try await sendFrame(frame)
        return try await awaitAck(for: id)
    }
}
