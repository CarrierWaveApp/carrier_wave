import CarrierWaveCore
import Foundation

// CW keyer commands forwarded over the RemoteOp link. Field can't
// share Sweep's BLE bond with the CW Bridge, so all keying goes
// through the existing TCP channel and Sweep applies it against the
// active bridge.

extension RemoteSweepCoordinator {
    /// Send a CW string through Sweep's bridge keyer. Returns true on success.
    @discardableResult
    func cwSendText(_ text: String) async -> Bool {
        await runCWCommand(label: "send CW") { client in
            try await client.sendCWText(text)
        }
    }

    /// Stop any active CW transmission.
    @discardableResult
    func cwStop() async -> Bool {
        await runCWCommand(label: "stop CW") { client in
            try await client.stopCW()
        }
    }

    /// Set Sweep's bridge keyer speed in WPM (5...60 effective).
    @discardableResult
    func cwSetSpeed(wpm: Int) async -> Bool {
        let clamped = UInt8(max(5, min(60, wpm)))
        return await runCWCommand(label: "set CW speed") { client in
            try await client.setCWSpeed(wpm: clamped)
        }
    }

    /// Play a stored CW memory slot (1...8) with optional template substitution
    /// context (e.g. `["call": "K1JT"]`).
    @discardableResult
    func cwPlaySlot(_ slot: UInt8, context: [String: String] = [:]) async -> Bool {
        await runCWCommand(label: "play CW slot") { client in
            try await client.playCWSlot(slot, context: context)
        }
    }

    /// Program a CW memory slot on Sweep. Returns true on ack.success.
    @discardableResult
    func cwSetSlot(_ slot: UInt8, label: String, text: String) async -> Bool {
        await runCWCommand(label: "program CW slot") { client in
            try await client.setCWSlot(slot, label: label, text: text)
        }
    }

    /// Setter routed through the class (rather than `private(set)`
    /// directly) so cross-file extensions like
    /// `RemoteSweepCoordinator+Session` can surface error strings
    /// without exposing a public setter on `lastError`.
    func recordError(_ message: String) {
        lastError = message
    }
}
