import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - CarrierWaveApp + WSJT-X

extension CarrierWaveApp {
    /// Attach the shared WSJT-X ingest service to this app's log and start the
    /// UDP listener if the user left it enabled (CAR-282). Called once from the
    /// launch task; `WsjtxFieldService.startIfEnabled()` runs again on every
    /// return to the foreground because iOS suspends the socket with the app.
    func configureWsjtxIngest() async {
        let service = WsjtxFieldService.shared
        service.configure(container: sharedModelContainer)
        await service.startIfEnabled()
    }
}
