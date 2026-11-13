import CarrierWaveData
import Foundation

// MARK: - Bridge Status Polling

extension RadioManager {
    /// Begin periodic interrogation of the bridge for current state. The
    /// firmware pushes one cached status frame at handshake time, but that
    /// can race the event-stream wiring or be missed entirely on a silent
    /// BLE reconnect — polling closes that gap so the USB indicator and
    /// keyer row settle to the correct value within a few seconds.
    ///
    /// Cancels any prior poll task. Stops on transport reset.
    func startBridgeStatusPolling(bridge: BridgeProtocol) {
        bridgeStatusPollTask?.cancel()
        bridgeStatusPollTask = Task { [weak self] in
            try? await bridge.requestStatus()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else {
                    break
                }
                guard let self, bridgeIsFramed else {
                    break
                }
                try? await bridge.requestStatus()
            }
        }
    }
}
