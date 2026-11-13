import CarrierWaveData
import Foundation

// MARK: - Bridge slot mirroring

extension RadioManager {
    /// Drop the per-slot `BridgeSlotState` for every slot. Companion to
    /// `resetBridgeState()`; lifted out so the parent file stays under the
    /// 500-line cap.
    func clearBridgeSlotStates() {
        for state in slotStates.values {
            state.bridge = nil
        }
    }

    /// Mirror the legacy `bridge*` fields on RadioManager into the matching
    /// slot's `BridgeSlotState`. Called from the BLE / event observers so
    /// new (slot-aware) consumers can read state without retrofitting every
    /// mutation site. The single-bridge legacy fields remain authoritative.
    func mirrorBridgeStateToSlot() {
        guard let sessionId = activeBridgeSessionId,
              let slot = slotForSession(sessionId),
              let bridgeState = slotStates[slot]?.bridge
        else {
            return
        }
        bridgeState.firmwareVersion = bridgeFirmwareVersion
        bridgeState.capabilities = bridgeCapabilities
        bridgeState.usbConnected = bridgeUSBConnected
        bridgeState.detectedRadio = bridgeDetectedRadio
        bridgeState.detecting = bridgeDetecting
        bridgeState.isFramed = bridgeIsFramed
        bridgeState.hasCWKeyer = bridgeHasCWKeyer
        bridgeState.cwSendingSlot = bridgeCWSendingSlot
        bridgeState.cwSpeed = bridgeCWSpeed
        bridgeState.cwFlags = bridgeCWFlags
        bridgeState.cwBufferDepth = bridgeCWBufferDepth
    }
}
