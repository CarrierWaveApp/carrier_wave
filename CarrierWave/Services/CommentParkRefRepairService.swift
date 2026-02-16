import CarrierWaveCore
import Foundation
import SwiftData

/// One-time backfill: extract park references from ADIF comment (notes) fields
/// on QSOs that have no parkReference but contain valid park refs in their notes.
/// WSJT-X and other loggers often put the park in the comment field rather than
/// MY_SIG_INFO, so QSOs imported before the extraction logic was added may be missing them.
actor CommentParkRefRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct BackfillResult: Sendable {
        let scanned: Int
        let updated: Int
    }

    let container: ModelContainer

    /// Run the backfill in batches. Returns counts of QSOs scanned and updated.
    func backfill() throws -> BackfillResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let batchSize = 500
        var totalScanned = 0
        var totalUpdated = 0
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate<QSO> { qso in
                    (qso.parkReference == nil || (qso.parkReference ?? "").isEmpty)
                        && qso.notes != nil
                        && !qso.isHidden
                }
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset

            let candidates = try context.fetch(descriptor)
            if candidates.isEmpty {
                break
            }

            totalScanned += candidates.count

            for qso in candidates {
                guard let notes = qso.notes,
                      let extracted = ParkReference.extractFromFreeText(notes)
                else {
                    continue
                }
                qso.parkReference = extracted
                totalUpdated += 1
            }

            if totalUpdated > 0 {
                try context.save()
            }

            if candidates.count < batchSize {
                break
            }
            offset += batchSize
        }

        return BackfillResult(scanned: totalScanned, updated: totalUpdated)
    }
}
