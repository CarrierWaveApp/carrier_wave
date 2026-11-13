import CarrierWaveData
import Foundation
import OSLog

private let slotLogger = Logger(subsystem: "com.jsvana.CWSweep", category: "RadioManager.Slots")

/// Map SS P2=5 (SPAN) P3 code to kHz.
/// Per FTDX10 CAT manual: 2=5, 3=10, 4=20, 5=50, 6=100, 7=200, 8=500, 9=1000
private func scopeSpanFromCode(_ code: Int) -> Double {
    switch code {
    case 2: 5
    case 3: 10
    case 4: 20
    case 5: 50
    case 6: 100
    case 7: 200
    case 8: 500
    case 9: 1_000
    default: 0
    }
}

// MARK: - Slot bookkeeping

extension RadioManager {
    /// Find the first slot in declaration order that doesn't yet hold a
    /// session. Returns nil when all slots are full.
    func nextAvailableSlot() -> RadioSlot? {
        RadioSlot.allCases.first { slots[$0] == nil }
    }

    /// Reverse lookup: which slot owns this session, if any.
    func slotForSession(_ sessionId: UUID) -> RadioSlot? {
        slots.first { $0.value == sessionId }?.key
    }

    /// Slot already holding a session for the given port path or BLE peripheral.
    /// Used by `connect(...)` to refuse double-binding the same physical radio
    /// across slots.
    func slotForPortPath(_ path: String) -> RadioSlot? {
        guard !path.isEmpty else {
            return nil
        }
        return slotStates.first { $0.value.connectedPortPath == path }?.key
    }

    /// Returns the slot state for the focused slot, if any. Used by legacy
    /// read paths and the polling loop's mirror write.
    var focusedSlotState: RadioSlotState? {
        slotStates[focusedSlot]
    }

    /// Register a fresh `RadioSlotState` for a newly-connected session.
    /// Called from `connect(profile:)` and `connectBridge(...)` paths.
    /// Honors `pendingConnectSlot` when set (caller-pinned slot); otherwise
    /// picks the first available slot.
    func registerSlotState(
        sessionId: UUID,
        profile: RadioProfile,
        portPath: String?
    ) -> RadioSlot? {
        let preferred = pendingConnectSlot
        pendingConnectSlot = nil
        let resolvedSlot: RadioSlot? =
            if let preferred, slots[preferred] == nil {
                preferred
            } else {
                nextAvailableSlot()
            }
        guard let slot = resolvedSlot else {
            slotLogger.warning("No free slot for new session \(sessionId)")
            return nil
        }
        let state = RadioSlotState(
            slot: slot,
            sessionId: sessionId,
            profile: profile
        )
        state.connectedPortPath = portPath
        state.connectedRadioName = profile.name
        state.contestRole = contestRole(for: slot)
        slots[slot] = sessionId
        slotStates[slot] = state
        // First connect promotes that slot to focused.
        if slotStates.count == 1 {
            focusedSlot = slot
        }
        return slot
    }

    /// Drop the slot owning this session, if any.
    func unregisterSlot(sessionId: UUID) {
        guard let slot = slotForSession(sessionId) else {
            return
        }
        slots.removeValue(forKey: slot)
        slotStates.removeValue(forKey: slot)
        // If the focused slot was the one removed, fall back to any other
        // connected slot. Otherwise keep current focus.
        if focusedSlot == slot, let other = slots.keys.min(by: { $0.ordinal < $1.ordinal }) {
            focusedSlot = other
        }
    }

    /// Drop every slot. Counterpart for `disconnectAll()`.
    func unregisterAllSlots() {
        slots.removeAll()
        slotStates.removeAll()
        focusedSlot = .a
    }
}

// MARK: - Scope span hook

extension RadioManager {
    /// Install a raw-frame hook that parses Yaesu SS05 scope span responses.
    /// Writes into the session's slot state and mirrors into the legacy
    /// `scopeSpanKHz` for the focused slot.
    func installScopeSpanHook(on session: RadioSession, sessionId: UUID) async {
        await session.setOnRawFrame { [weak self] frame in
            guard let str = String(data: frame, encoding: .ascii),
                  str.hasPrefix("SS05")
            else {
                return
            }
            let spanIdx = str.index(str.startIndex, offsetBy: 4)
            if let spanCode = str[spanIdx].wholeNumberValue {
                let spanKHz = scopeSpanFromCode(spanCode)
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    if let slot = slotForSession(sessionId), let state = slotStates[slot] {
                        state.scopeSpanKHz = spanKHz
                        if slot == focusedSlot {
                            scopeSpanKHz = spanKHz
                        }
                    } else {
                        scopeSpanKHz = spanKHz
                    }
                }
            }
        }
    }
}

// MARK: - Polling loop helpers

extension RadioManager {
    /// Polls every connected session, writing into its `RadioSlotState` and
    /// (for the focused slot only) mirroring into the legacy singular fields
    /// on `RadioManager` so existing UI consumers keep working.
    func pollAllSessions() async {
        while !Task.isCancelled {
            for (slot, sessionId) in slots {
                guard let session = sessions[sessionId],
                      let state = slotStates[slot]
                else {
                    continue
                }
                let snapshot = await session.state
                state.frequency = snapshot.frequency
                state.mode = snapshot.mode
                state.xitEnabled = snapshot.xitEnabled
                state.ritEnabled = snapshot.ritEnabled
                state.ritXitOffset = snapshot.ritXitOffset
                state.isTransmitting = snapshot.isTransmitting
                if slot == focusedSlot {
                    frequency = snapshot.frequency
                    mode = snapshot.mode
                    xitEnabled = snapshot.xitEnabled
                    ritEnabled = snapshot.ritEnabled
                    ritXitOffset = snapshot.ritXitOffset
                    isTransmitting = snapshot.isTransmitting
                }
            }
            if isConnected {
                iqPanadapter.updateTuning(
                    frequencyMHz: frequency,
                    mode: mode,
                    ritHz: ritXitOffset,
                    ritEnabled: ritEnabled,
                    transmitting: isTransmitting
                )
            }
            if let activeTransport = activeSCULAN10 {
                lastDebugStats = await sculan10Stats(activeTransport)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
