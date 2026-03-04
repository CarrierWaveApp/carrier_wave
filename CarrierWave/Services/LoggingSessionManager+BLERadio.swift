import CarrierWaveData
import Foundation

// MARK: - BLE Radio Integration

extension LoggingSessionManager {
    /// Connect BLE radio if configured, start polling, wire callbacks
    func connectBLERadio() {
        let service = BLERadioService.shared
        guard service.isConfigured else {
            return
        }

        // Detect protocol from the session's rig name before connecting
        service.setProtocolFromRig(activeSession?.myRig)

        // Wire up radio → app callbacks
        service.onRadioFrequencyChanged = { [weak self] freq in
            self?.handleRadioFrequencyChange(freq)
        }
        service.onRadioModeChanged = { [weak self] mode in
            self?.handleRadioModeChange(mode)
        }

        service.connectToSavedDevice()
    }

    /// Disconnect BLE radio and clear callbacks
    func disconnectBLERadio() {
        let service = BLERadioService.shared
        service.onRadioFrequencyChanged = nil
        service.onRadioModeChanged = nil
        service.disconnect()
    }

    /// Handle frequency change from the physical radio
    func handleRadioFrequencyChange(_ frequencyMHz: Double) {
        guard let session = activeSession else {
            return
        }

        // Only update if delta > 100 Hz (0.0001 MHz)
        if let current = session.frequency,
           abs(current - frequencyMHz) < 0.0001
        {
            return
        }

        _ = updateFrequency(frequencyMHz)
    }

    /// Handle mode change from the physical radio
    func handleRadioModeChange(_ mode: String) {
        guard let session = activeSession else {
            return
        }

        guard session.mode != mode else {
            return
        }
        updateMode(mode)
    }

    /// Send frequency to the physical radio (app → radio direction)
    func sendFrequencyToRadio(_ frequencyMHz: Double) {
        let service = BLERadioService.shared
        guard service.isConnected else {
            return
        }
        service.setFrequency(frequencyMHz)
    }

    /// Send mode to the physical radio (app → radio direction)
    func sendModeToRadio(_ mode: String) {
        let service = BLERadioService.shared
        guard service.isConnected else {
            return
        }
        service.setMode(mode)
    }
}
