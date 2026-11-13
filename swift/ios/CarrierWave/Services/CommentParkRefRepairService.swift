import CarrierWaveData
import Foundation
import SwiftData

/// One-time backfill: extract park references from ADIF comment (notes) fields
/// on QSOs that have no theirParkReference but contain valid park refs in their notes.
/// Comment-extracted refs are the other station's park (hunting), not our activation park.
///
/// Façade over `BatchedRewrite`.
actor CommentParkRefRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct BackfillResult {
        let scanned: Int
        let updated: Int
    }

    let container: ModelContainer

    /// Run the backfill in batches. Returns counts of QSOs scanned and updated.
    func backfill() async throws -> BackfillResult {
        let result = try await BatchedRewrite<QSO>(
            label: "commentParkRef.backfill",
            container: container,
            predicate: #Predicate<QSO> { qso in
                !qso.isActivityLogQSO
                    && qso.theirParkReference == nil
                    && qso.notes != nil
                    && !qso.isHidden
            }
        ) { qso, _ in
            guard let notes = qso.notes,
                  let extracted = ParkReference.extractFromFreeText(notes)
            else {
                return false
            }
            qso.theirParkReference = extracted
            return true
        }.run()

        return BackfillResult(scanned: result.scanned, updated: result.mutated)
    }
}
