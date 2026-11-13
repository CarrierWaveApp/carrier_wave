import CarrierWaveData
import SwiftData
import UIKit

/// Repair: clear upload flags on PoLo metadata pseudo-QSOs (CAR-278).
///
/// Ham2K PoLo writes its marker pseudo-modes (`QSOMode.metadataModes`) into
/// the operation log as QSO-shaped rows. Before this fix the LoFi *sync* path
/// (`QSOProcessingActor.createNewQSOFromGroup`), orphan repair and QRZ dead-state
/// repair all created or re-armed `needsUpload=true` presence rows for them, so
/// they showed up as "pending upload" forever — no uploader will ever send them.
///
/// This clears `needsUpload` (and any stale `isSubmitted`) on every presence row
/// whose QSO is a metadata mode, for every service. Idempotent: a second run
/// finds nothing to change. Runs once at launch via `DataRepairService` and is
/// also the implementation behind the per-sync `clearMetadataUploadFlags` pass.
///
/// Batched over the `needsUpload == true` predicate with fresh contexts. Cleared
/// rows drop out of the predicate after save, so the offset only advances past
/// the rows that were *not* cleared (the same bookkeeping `QSOProcessingActor`'s
/// clear-flag repairs use; `BatchedRewrite` would skip rows here).
/// Saves route through `OffMainStoreSeam.commitPresence` so cw-store is written
/// first in `.on` mode.
actor MetadataUploadFlagRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer, batchSize: Int = 500) {
        self.container = container
        self.batchSize = batchSize
    }

    // MARK: Internal

    struct RepairResult: Sendable, Equatable {
        /// Presence rows whose `needsUpload` flag was cleared.
        let clearedCount: Int
        /// Cleared rows grouped by service.
        let byService: [ServiceType: Int]
    }

    let container: ModelContainer
    let batchSize: Int

    /// Clear `needsUpload` on every presence row belonging to a metadata-mode QSO.
    func repair() async throws -> RepairResult {
        var clearedCount = 0
        var byService: [ServiceType: Int] = [:]
        var offset = 0

        while true {
            try Task.checkCancellation()
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate<ServicePresence> { $0.needsUpload },
                limit: batchSize,
                offset: offset,
                relationshipKeyPathsForPrefetching: [\.qso]
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            var cleared: [ServicePresence] = []
            for presence in batch {
                guard let qso = presence.qso, !qso.isDeleted,
                      QSOMode.isMetadata(qso.mode)
                else {
                    continue
                }
                presence.needsUpload = false
                presence.isSubmitted = false
                presence.cloudDirtyFlag = true
                cleared.append(presence)
                byService[presence.serviceType, default: 0] += 1
            }

            if !cleared.isEmpty {
                try OffMainStoreSeam.commitPresence(cleared, in: context)
            }
            clearedCount += cleared.count
            // Cleared rows leave the needsUpload predicate after save.
            offset += batch.count - cleared.count
            if batch.count < batchSize {
                break
            }
            await Task.yield()
        }

        return RepairResult(clearedCount: clearedCount, byService: byService)
    }
}
