import CarrierWaveCore
import CarrierWaveData
import Foundation

//
// CW keyer commands and snapshots split off the main RemoteOpService body to
// keep that type under SwiftLint's 300-line cap. Each handler routes through
// `RadioManager`'s bridge surface; failures surface as a non-success Ack
// rather than an error frame so the iOS client can show inline status.

@MainActor
extension RemoteOpService {
    /// Snapshot of current keyer state for `cw.keyer` events. Returns nil when
    /// no radio is connected — without an active radio there is no meaningful
    /// `radioID` to report against. `keyerAvailable` is true if any path can
    /// key (bridge, WinKeyer, or the active radio's CAT handler); the
    /// bridge-specific fields stay populated only when the bridge is the
    /// active path.
    func currentCWStatusSnapshot() -> CWStatusEvent? {
        guard let manager = radioManager else {
            return nil
        }
        let radioID = manager.activeRadioId?.uuidString ?? "active"
        let available: Bool = if let winKeyer = winKeyerManager {
            manager.cwKeyerAvailable(fallback: winKeyer)
        } else {
            manager.isBridgeKeyerAvailable
        }
        return CWStatusEvent(
            radioID: radioID,
            keyerAvailable: available,
            wpm: manager.bridgeCWSpeed,
            bufferDepth: manager.bridgeCWBufferDepth,
            sendingSlot: manager.bridgeCWSendingSlot.map { UInt8(clamping: $0) },
            isSending: manager.bridgeCWIsSending,
            timestamp: Date()
        )
    }

    /// Forwarded by RemoteOpConnection when a `commandSendCW` frame arrives.
    /// Routes through the unified CW path (bridge → WinKeyer → CAT) so the
    /// straight-key tap UI on Field works whether Sweep is talking to the
    /// rig over BLE bridge, USB serial CAT, or TCP CAT (e.g. SCU-LAN10).
    func handleSendCW(_ command: SendCWCommand) async -> Ack {
        guard let manager = radioManager, let winKeyer = winKeyerManager else {
            return Self.noKeyerAck(requestID: command.requestID)
        }
        let ok = await manager.sendCW(command.text, fallback: winKeyer)
        return Ack(
            requestID: command.requestID,
            success: ok,
            detail: ok ? nil : "no CW path available"
        )
    }

    /// Forwarded by RemoteOpConnection when a `commandStopCW` frame arrives.
    func handleStopCW(_ command: StopCWCommand) async -> Ack {
        guard let manager = radioManager, let winKeyer = winKeyerManager else {
            return Self.noKeyerAck(requestID: command.requestID)
        }
        let ok = await manager.stopCW(fallback: winKeyer)
        return Ack(
            requestID: command.requestID,
            success: ok,
            detail: ok ? nil : "no CW abort available"
        )
    }

    /// Forwarded by RemoteOpConnection when a `commandSetCWSpeed` frame arrives.
    func handleSetCWSpeed(_ command: SetCWSpeedCommand) async -> Ack {
        guard let manager = radioManager, let winKeyer = winKeyerManager else {
            return Self.noKeyerAck(requestID: command.requestID)
        }
        let clamped = max(5, min(60, command.wpm))
        let ok = await manager.setCWSpeed(Int(clamped), fallback: winKeyer)
        return Ack(
            requestID: command.requestID,
            success: ok,
            detail: ok ? nil : "speed control unavailable on this CW path"
        )
    }

    /// Forwarded by RemoteOpConnection when a `commandPlayCWSlot` frame arrives.
    /// Builds the macro context from Sweep's live Quick Entry (callsign,
    /// RST, name, state) and merges in any keys the client supplied (rare —
    /// the iOS keyer no longer maintains a parallel entry box). Rejects with
    /// `Ack(success: false)` if the slot still has unsatisfied macros after
    /// merging, so the operator gets a clear "missing CALL" rather than a
    /// silent no-op.
    func handlePlayCWSlot(_ command: PlayCWSlotCommand) async -> Ack {
        guard let manager = requireBridgeKeyer(requestID: command.requestID) else {
            return Self.bridgeUnavailableAck(requestID: command.requestID)
        }
        guard (1 ... 8).contains(command.slot) else {
            return Ack(requestID: command.requestID, success: false, detail: "slot out of range")
        }
        guard let keyer = cwKeyerService else {
            return Ack(requestID: command.requestID, success: false, detail: "keyer unavailable")
        }
        let template = await keyer.message(for: Int(command.slot))
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Ack(requestID: command.requestID, success: false, detail: "slot \(command.slot) is empty")
        }
        let context = mergedMacroContext(clientSupplied: command.context)
        let missing = RemoteCWMacros.missingMacros(in: template, context: context)
        guard missing.isEmpty else {
            return Ack(
                requestID: command.requestID,
                success: false,
                detail: "missing: " + missing.map { "{\($0)}" }.joined(separator: " ")
            )
        }
        let expanded = RemoteCWMacros.expand(template, context: context)
        await manager.bridgeSendCW(expanded)
        return Ack(requestID: command.requestID, success: true)
    }

    /// Build the active macro context from Sweep's live state: parsed Quick
    /// Entry tokens first, falling back to the callsign-info lookup, then
    /// to the operator's keychain callsign and the radio's current freq.
    /// Any keys the client explicitly supplied win — they're either typed
    /// values from a future Field surface or one-off overrides.
    func currentCWMacroContext() -> [String: String] {
        var ctx: [String: String] = [:]
        if let mycall = try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.currentCallsign
        ), !mycall.isEmpty {
            ctx["MYCALL"] = mycall
        }
        if let state = selectionState {
            let parsed = state.parsedQuickEntry
            if let call = parsed?.callsign ?? state.entryCallsign, !call.isEmpty {
                let upper = call.uppercased()
                ctx["CALL"] = upper
                ctx["HISCALL"] = upper
            }
            if let rst = parsed?.rstSent, !rst.isEmpty {
                ctx["RST"] = rst
            }
            if let name = state.entryCallsignName, !name.isEmpty {
                ctx["NAME"] = name
            }
            if let st = parsed?.state ?? state.entryCallsignState, !st.isEmpty {
                ctx["HISSTATE"] = st.uppercased()
            }
        }
        if let manager = radioManager, manager.frequency > 0 {
            ctx["FREQ"] = String(format: "%.3f", manager.frequency)
        }
        return ctx
    }

    private func mergedMacroContext(clientSupplied: [String: String]) -> [String: String] {
        var merged = currentCWMacroContext()
        for (key, value) in clientSupplied where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged[key] = value
        }
        return merged
    }

    /// Snapshot of every memory slot Sweep currently knows about (1...8).
    /// Returns nil only when the keyer service hasn't been wired in yet —
    /// that should never happen post-init via `SharedEnvironment`.
    func currentCWSlotsSnapshot() async -> CWSlotsEvent? {
        guard let keyer = cwKeyerService else {
            return nil
        }
        let raw = await keyer.slotSnapshot()
        let slots = raw.map { entry in
            RemoteCWSlot(
                id: UInt8(clamping: entry.id),
                label: entry.label,
                text: entry.text
            )
        }
        return CWSlotsEvent(slots: slots)
    }

    /// Forwarded by RemoteOpConnection when a `commandSetCWSlot` frame
    /// arrives. Persists the new label + text on Sweep's keyer service and,
    /// when a bridge with keyer capability is connected, mirrors the text
    /// into the bridge's slot memory so subsequent `playCWSlot` frames key
    /// the right message. Broadcasts the updated slot table on `cw.slots`.
    func handleSetCWSlot(_ command: SetCWSlotCommand) async -> Ack {
        guard let keyer = cwKeyerService else {
            return Ack(requestID: command.requestID, success: false, detail: "keyer unavailable")
        }
        guard (1 ... 8).contains(command.slot) else {
            return Ack(requestID: command.requestID, success: false, detail: "slot out of range")
        }
        await keyer.setMessage(slot: Int(command.slot), text: command.text)
        await keyer.setLabel(slot: Int(command.slot), label: command.label)
        if let manager = radioManager, manager.isBridgeKeyerAvailable {
            await manager.bridgeSetCWSlot(command.slot, text: command.text)
        }
        if let snapshot = await currentCWSlotsSnapshot() {
            broadcast(.eventCWSlots(snapshot), topic: .cwSlots)
        }
        return Ack(requestID: command.requestID, success: true)
    }

    /// Slot playback is bridge-specific (slot memory lives in the dongle),
    /// so this helper still gates strictly on the bridge.
    private func requireBridgeKeyer(requestID _: UUID) -> RadioManager? {
        guard let manager = radioManager, manager.isBridgeKeyerAvailable else {
            return nil
        }
        return manager
    }

    private static func bridgeUnavailableAck(requestID: UUID) -> Ack {
        Ack(requestID: requestID, success: false, detail: "bridge keyer unavailable")
    }

    private static func noKeyerAck(requestID: UUID) -> Ack {
        Ack(requestID: requestID, success: false, detail: "no CW path available")
    }
}
