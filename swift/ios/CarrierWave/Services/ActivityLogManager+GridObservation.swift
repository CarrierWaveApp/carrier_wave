import CarrierWaveData
import Observation
import SwiftData

// MARK: - Grid Observation

extension ActivityLogManager {
    /// Observe location service grid changes and update the active log.
    /// Called when location tracking starts (profile with `useCurrentLocation`).
    func startGridObservation() {
        observeGridChanges()
    }

    func observeGridChanges() {
        withObservationTracking {
            _ = self.locationService.currentGrid
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let log = activeLog else {
                    return
                }
                if let newGrid = locationService.currentGrid,
                   newGrid != log.currentGrid
                {
                    log.currentGrid = newGrid
                    log.cloudDirtyFlag = true
                    // Route through the seam so the grid update is cw-store-canonical
                    // under `.on` (was a raw save that only the passive mirror caught).
                    try? EntityWriteSink.commitUpsert(log, in: modelContext)
                }
                observeGridChanges()
            }
        }
    }
}
