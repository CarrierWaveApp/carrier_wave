import Foundation
import SwiftData

// MARK: - Mark-All-Dirty (Force Full Re-Sync)

extension CloudSyncJournalEngine {
    /// Mark every syncable record's `cloudDirtyFlag` to `true`. QSOs and
    /// ServicePresence run in batches of `BoundedDescriptor.maxLimit` with a
    /// fresh `ModelContext` per batch so peak memory stays bounded on logs
    /// with 100K+ records (per swift/CLAUDE.md performance rules).
    func markAllRecordsDirtyImpl() {
        let container = modelContext.container

        // QSO authority flipped to the store: mark there (Rust skips metadata
        // modes). Otherwise fall back to the batched SwiftData mark.
        if let qsoJournalStore {
            _ = try? qsoJournalStore.markAllDirty()
        } else {
            markDirtyInBatches(container: container) { (qso: QSO) in
                guard !QSOMode.isMetadata(qso.mode) else {
                    return
                }
                qso.cloudDirtyFlag = true
            }
        }

        markDirtyInBatches(container: container) { (presence: ServicePresence) in
            presence.cloudDirtyFlag = true
        }

        let sessionDescriptor = FetchDescriptor<LoggingSession>()
        if let sessions = try? modelContext.fetch(sessionDescriptor) {
            for session in sessions {
                session.cloudDirtyFlag = true
            }
        }

        let metadataDescriptor = FetchDescriptor<ActivationMetadata>()
        if let metadata = try? modelContext.fetch(metadataDescriptor) {
            for am in metadata {
                am.cloudDirtyFlag = true
            }
        }

        let spotDescriptor = FetchDescriptor<SessionSpot>()
        if let spots = try? modelContext.fetch(spotDescriptor) {
            for spot in spots {
                spot.cloudDirtyFlag = true
            }
        }

        let logDescriptor = FetchDescriptor<ActivityLog>()
        if let logs = try? modelContext.fetch(logDescriptor) {
            for log in logs {
                log.cloudDirtyFlag = true
            }
        }

        try? modelContext.save()
    }

    private func markDirtyInBatches<T: PersistentModel>(
        container: ModelContainer,
        apply: (T) -> Void
    ) {
        let batchSize = BoundedDescriptor<T>.maxLimit
        var offset = 0

        while true {
            let batchContext = ModelContext(container)
            batchContext.autosaveEnabled = false
            let descriptor = BoundedDescriptor<T>(
                limit: batchSize,
                offset: offset
            )

            guard let batch = try? batchContext.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }

            for item in batch {
                apply(item)
            }
            try? batchContext.save()

            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }
    }
}
