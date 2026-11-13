import CarrierWaveData
import Foundation

// MARK: - Radio Control Commands

extension RadioManager {
    /// Resolve the session for a tune call. `slot == nil` ⇒ focused slot.
    /// Returns nil when the slot has no session (or, in single-radio mode,
    /// when nothing is connected at all).
    private func session(for slot: RadioSlot?) -> RadioSession? {
        if let slot {
            guard let sessionId = slots[slot] else {
                return nil
            }
            return sessions[sessionId]
        }
        if let focused = slots[focusedSlot], let session = sessions[focused] {
            return session
        }
        // Fall back to legacy `activeRadioId` so the tune API still works
        // before the slot infrastructure has populated (e.g. during the
        // narrow window between connect and registerSlotState).
        guard let id = activeRadioId else {
            return nil
        }
        return sessions[id]
    }

    @discardableResult
    func tuneToFrequency(_ freqMHz: Double, slot: RadioSlot? = nil) async -> Bool {
        guard let session = session(for: slot) else {
            // No radio on this slot: record the operator's chosen frequency in
            // app state so manual tuning (radio palette, band-map click, vim
            // `:freq`) sticks and logged QSOs inherit it. Without this the
            // command silently no-ops whenever no radio is connected.
            applyManualFrequency(freqMHz, slot: slot)
            return true
        }
        return await session.tuneToFrequency(freqMHz)
    }

    @discardableResult
    func setMode(_ mode: String, slot: RadioSlot? = nil) async -> Bool {
        guard let session = session(for: slot) else {
            applyManualMode(mode, slot: slot)
            return true
        }
        return await session.setMode(mode, universalModeRawValue: nil)
    }

    /// Reflect a manually-chosen frequency into app state when no radio
    /// session can accept the tune command. Updates the target slot's state
    /// (if any) and mirrors into the legacy focused-slot field read by the
    /// logger, status bar, and band map. When a radio is connected the poll
    /// loop owns these fields, so this only runs while disconnected.
    private func applyManualFrequency(_ freqMHz: Double, slot: RadioSlot?) {
        let target = slot ?? focusedSlot
        slotStates[target]?.frequency = freqMHz
        if target == focusedSlot {
            frequency = freqMHz
            pushManualTuningToWaterfall()
        }
    }

    /// Mode counterpart to `applyManualFrequency`.
    private func applyManualMode(_ newMode: String, slot: RadioSlot?) {
        let target = slot ?? focusedSlot
        slotStates[target]?.mode = newMode
        if target == focusedSlot {
            mode = newMode
            pushManualTuningToWaterfall()
        }
    }

    /// With a radio connected, `pollAllSessions` feeds the external SDR
    /// waterfall from CAT state. Without one that loop never fires, so a
    /// direct-RF SDR user tuning a spot saw the log entry move but the
    /// waterfall stay put (CAR-121). Mirror the manual frequency/mode into
    /// the panadapter here instead. Cheap: `updateTuning` dedupes and is a
    /// no-op while the SDR input is disabled.
    private func pushManualTuningToWaterfall() {
        guard !isConnected else {
            return
        }
        iqPanadapter.updateTuning(
            frequencyMHz: frequency,
            mode: mode,
            ritHz: 0,
            ritEnabled: false,
            transmitting: false
        )
    }

    @discardableResult
    func setPTT(_ on: Bool, slot: RadioSlot? = nil) async -> Bool {
        guard let session = session(for: slot) else {
            return false
        }
        if on, pttInterlockEnabled {
            let target = slot ?? focusedSlot
            for (otherSlot, otherState) in slotStates where otherSlot != target && otherState.isTransmitting {
                commandLog.append(
                    direction: .status,
                    text: "PTT interlock: \(otherSlot.label) is transmitting — refused \(target.label)"
                )
                return false
            }
        }
        return await session.setPTT(on)
    }

    /// Whether the PTT interlock is enabled. Reads UserDefaults each call
    /// so toggles in the preferences popover take effect immediately.
    var pttInterlockEnabled: Bool {
        UserDefaults.standard.bool(forKey: "radio.pttInterlockEnabled")
    }

    @discardableResult
    func setXIT(_ on: Bool, slot: RadioSlot? = nil) async -> Bool {
        guard let session = session(for: slot) else {
            return false
        }
        return await session.setXIT(on)
    }

    @discardableResult
    func setXITOffset(_ hz: Int, slot: RadioSlot? = nil) async -> Bool {
        guard let session = session(for: slot) else {
            return false
        }
        return await session.setRITXITOffset(hz)
    }

    @discardableResult
    func clearRITXIT(slot: RadioSlot? = nil) async -> Bool {
        guard let session = session(for: slot) else {
            return false
        }
        return await session.clearRITXIT()
    }

    /// Tune to a frequency and mode, applying XIT settings if enabled.
    /// This consolidates the repeated tune-and-XIT pattern used across spot views.
    func tuneToSpot(
        frequencyMHz: Double,
        mode: String,
        autoXITEnabled: Bool,
        autoXITOffsetHz: Int,
        slot: RadioSlot? = nil
    ) async {
        let hasRadio = session(for: slot) != nil
        await tuneToFrequency(frequencyMHz, slot: slot)
        await setMode(mode, slot: slot)
        if !hasRadio {
            // Say where the tune went so the action is never a silent no-op.
            let destination = SpotTuneDestination.resolve(
                isRadioConnected: false,
                radioName: nil,
                sdrWaterfallEnabled: iqPanadapter.settings.enabled
            )
            if let line = destination.noRadioStatusLine(frequencyMHz: frequencyMHz, mode: mode) {
                commandLog.append(direction: .status, text: line)
            }
        }
        if autoXITEnabled, autoXITOffsetHz != 0 {
            await setXITOffset(autoXITOffsetHz, slot: slot)
            await setXIT(true, slot: slot)
        } else if autoXITEnabled {
            await setXIT(false, slot: slot)
        }
    }
}

// MARK: - Slot focus

extension RadioManager {
    /// Move user focus to the given slot. No-op if the slot has no session.
    /// Mirrors focused state into the legacy singular fields so existing UI
    /// readers see the new active radio without restarting the poll loop.
    func setFocusedSlot(_ slot: RadioSlot) {
        guard let sessionId = slots[slot], let state = slotStates[slot] else {
            return
        }
        focusedSlot = slot
        activeRadioId = sessionId
        frequency = state.frequency
        mode = state.mode
        xitEnabled = state.xitEnabled
        ritEnabled = state.ritEnabled
        ritXitOffset = state.ritXitOffset
        isTransmitting = state.isTransmitting
        scopeSpanKHz = state.scopeSpanKHz
        connectedPortPath = state.connectedPortPath
        connectedRadioName = state.connectedRadioName
        commandLog.append(direction: .status, text: "Focus → \(slot.label)")
        if audioFollowsFocus {
            setAudioRoutedSlot(slot)
        }
    }

    /// Swap the tuned frequency between two slots. SO2R staple — used by
    /// the `swap` command in the radio palette and the ⌃⌘S shortcut.
    /// No-op when either slot is unpopulated.
    func swapFrequencies(_ first: RadioSlot, _ second: RadioSlot) async {
        guard let firstFreq = slotStates[first]?.frequency,
              let secondFreq = slotStates[second]?.frequency,
              firstFreq > 0, secondFreq > 0
        else {
            return
        }
        await tuneToFrequency(secondFreq, slot: first)
        await tuneToFrequency(firstFreq, slot: second)
        commandLog.append(direction: .status, text: "Swapped \(first.shortLabel) ↔ \(second.shortLabel)")
    }
}
