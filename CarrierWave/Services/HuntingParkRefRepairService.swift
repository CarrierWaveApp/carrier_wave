import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: fix QSOs where comment-extracted park references were incorrectly
/// assigned to `parkReference` (activator field) instead of `theirParkReference` (hunter field).
/// This caused hunting QSOs to be treated as activations and uploaded to POTA as bogus
/// single-QSO activations.
actor HuntingParkRefRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult: Sendable {
        let scanned: Int
        let repaired: Int
    }

    let container: ModelContainer

    /// Run the repair in batches. Returns counts of QSOs scanned and repaired.
    func repair() throws -> RepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let batchSize = 500
        var totalScanned = 0
        var totalRepaired = 0
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate<QSO> { qso in
                    qso.parkReference != nil
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
                guard shouldRepair(qso) else {
                    continue
                }
                // Move parkReference → theirParkReference (if their is empty)
                if qso.theirParkReference == nil || (qso.theirParkReference ?? "").isEmpty {
                    qso.theirParkReference = qso.parkReference
                }
                qso.parkReference = nil

                // Clear POTA needsUpload flags since this isn't an activation
                clearPOTAUploadFlags(for: qso, context: context)
                totalRepaired += 1
            }

            if candidates.count < batchSize {
                break
            }
            offset += batchSize
        }

        if totalRepaired > 0 {
            try context.save()
        }

        return RepairResult(scanned: totalScanned, repaired: totalRepaired)
    }

    // MARK: Private

    /// Determine if a QSO's parkReference came from comment extraction (not ADIF fields).
    private func shouldRepair(_ qso: QSO) -> Bool {
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

        // No rawADIF: check if parkReference matches what extractFromFreeText would produce
        guard let notes = qso.notes else {
            return false
        }
        let extracted = ParkReference.extractFromFreeText(notes)
        return extracted == parkRef
    }

    /// Clear POTA ServicePresence needsUpload flags for a QSO that isn't an activation.
    private func clearPOTAUploadFlags(for qso: QSO, context: ModelContext) {
        for presence in qso.servicePresence where presence.serviceType == .pota {
            if presence.needsUpload {
                presence.needsUpload = false
            }
        }
    }
}
