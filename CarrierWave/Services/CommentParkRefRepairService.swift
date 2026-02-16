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

    /// Run the backfill. Returns counts of QSOs scanned and updated.
    func backfill() throws -> BackfillResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch QSOs that have notes but no park reference
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                (qso.parkReference == nil || (qso.parkReference ?? "").isEmpty)
                    && qso.notes != nil
                    && !qso.isHidden
            }
        )
        descriptor.propertiesToFetch = [\.parkReference, \.notes]

        let candidates = try context.fetch(descriptor)
        var updated = 0

        for qso in candidates {
            guard let notes = qso.notes,
                  let extracted = ParkReference.extractFromFreeText(notes)
            else {
                continue
            }
            qso.parkReference = extracted
            updated += 1
        }

        if updated > 0 {
            try context.save()
        }

        return BackfillResult(scanned: candidates.count, updated: updated)
    }
}
