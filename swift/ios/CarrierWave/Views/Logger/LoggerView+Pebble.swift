import CarrierWaveData
import SwiftUI

// MARK: - LoggerView Pebble Bridge

extension LoggerView {
    /// Listens for `didReceivePebbleLogQSO` posted by `PebbleBridgeService`
    /// when the watch presses SELECT on the session screen. Treats the press
    /// as a remote "Enter" on whatever is currently typed — the iPhone form
    /// remains the source of truth for callsign and field values.
    func applyPebbleHandlers(_ content: some View) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .didReceivePebbleLogQSO)
        ) { _ in
            guard canLog else {
                return
            }
            handleInputSubmit()
        }
    }
}
