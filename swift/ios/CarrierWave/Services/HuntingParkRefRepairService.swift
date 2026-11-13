import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: fix QSOs where comment-extracted park references were incorrectly
/// assigned to `parkReference` (activator field) instead of `theirParkReference` (hunter field).
/// This caused hunting QSOs to be treated as activations and uploaded to POTA as bogus
/// single-QSO activations.
///
/// Façade over `BatchedRewrite`.
actor HuntingParkRefRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult {
        let scanned: Int
        let repaired: Int
    }

    let container: ModelContainer

    /// Run the repair in batches. Returns counts of QSOs scanned and repaired.
    func repair() async throws -> RepairResult {
        let result = try await BatchedRewrite<QSO>(
            label: "huntingParkRef.repair",
            container: container,
            predicate: #Predicate<QSO> { qso in
                qso.parkReference != nil && qso.notes != nil && !qso.isHidden
            },
            mutate: { qso, _ in
                guard Self.shouldRepair(qso) else {
                    return false
                }

                if qso.theirParkReference == nil || (qso.theirParkReference ?? "").isEmpty {
                    qso.theirParkReference = qso.parkReference
                }
                qso.parkReference = nil

                // This isn't an activation — clear POTA upload flags.
                for presence in qso.servicePresence
                    where presence.serviceType == .pota && presence.needsUpload
                {
                    presence.needsUpload = false
                }
                return true
            },
            // Each repaired QSO co-mutates its ServicePresence rows, so route the
            // whole (QSO + presence) graph canonically — a half-route would drop the
            // presence flips from cw-store in `.on` mode.
            commit: { qsos, context in
                try OffMainStoreSeam.commitQSOsWithPresence(qsos, in: context)
            }
        ).run()

        return RepairResult(scanned: result.scanned, repaired: result.mutated)
    }

    // MARK: Private

    /// Determine if a QSO's parkReference came from comment extraction (not ADIF fields).
    private static func shouldRepair(_ qso: QSO) -> Bool {
        guard let parkRef = qso.parkReference, !parkRef.isEmpty else {
            return false
        }

        // If rawADIF exists, check whether it contains MY_SIG_INFO or MY_POTA_REF.
        // If neither field is present, the parkReference must have come from comment extraction.
        if let rawADIF = qso.rawADIF, !rawADIF.isEmpty {
            let upper = rawADIF.uppercased()
            let hasMyField = upper.contains("MY_SIG_INFO") || upper.contains("MY_POTA_REF")
            return !hasMyField
        }

        // No rawADIF: check if parkReference matches what extractFromFreeText would produce.
        guard let notes = qso.notes else {
            return false
        }
        let extracted = ParkReference.extractFromFreeText(notes)
        return extracted == parkRef
    }
}
