import CarrierWaveData
import Foundation
import SwiftData

// MARK: - Dead State Repair (QRZ + POTA)

extension QSOProcessingActor {
    // MARK: - QRZ Dead State Repair

    /// Result of repairing QRZ dead-state QSOs
    struct QRZDeadStateRepairResult {
        let repairedCount: Int
        let rejectedNonPrimaryCount: Int
    }

    /// Repair QRZ ServicePresence records stuck in dead state.
    /// Dead state: isPresent=false, needsUpload=false, isSubmitted=false, uploadRejected=false.
    /// This happens when uploadToQRZ clears needsUpload but QRZ download never confirms the QSO.
    /// Only repairs QSOs matching the primary callsign — non-primary callsign QSOs are
    /// permanently marked uploadRejected to prevent an infinite repair/clear cycle (CAR-170).
    /// Uses batched fetching with fresh contexts to cap memory usage.
    func repairQRZDeadStateQSOs(
        primaryCallsign: String?,
        container: ModelContainer
    ) async throws -> QRZDeadStateRepairResult {
        let upperPrimary = primaryCallsign?.uppercased()
        var repairedCount = 0
        var rejectedCount = 0
        let batchSize = 500
        var offset = 0

        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate<ServicePresence> {
                    !$0.isPresent && !$0.needsUpload && !$0.isSubmitted && !$0.uploadRejected
                },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            let result = processDeadStateBatch(batch, upperPrimary: upperPrimary)
            if !result.modified.isEmpty {
                // Presence-only off-main save → cw-store first in `.on`, suppressed save.
                try OffMainStoreSeam.commitPresence(result.modified, in: context)
            }
            repairedCount += result.repaired
            rejectedCount += result.rejected
            offset += batch.count - result.modified.count
            await Task.yield()
        }

        return QRZDeadStateRepairResult(
            repairedCount: repairedCount,
            rejectedNonPrimaryCount: rejectedCount
        )
    }

    /// Outcome of one dead-state batch: per-category counts plus the modified
    /// presence objects so the caller can route them through the seam.
    struct DeadStateBatchResult {
        var repaired = 0
        var rejected = 0
        var modified: [ServicePresence] = []
    }

    /// Process a single batch of dead-state ServicePresence records.
    private func processDeadStateBatch(
        _ batch: [ServicePresence],
        upperPrimary: String?
    ) -> DeadStateBatchResult {
        var result = DeadStateBatchResult()

        for presence in batch {
            guard presence.serviceType == .qrz else {
                continue
            }
            // CAR-278: PoLo marker rows legitimately sit at isPresent=false /
            // needsUpload=false forever; re-arming them would fight the metadata clear.
            guard let qso = presence.qso, !qso.isHidden, !QSOMode.isMetadata(qso.mode) else {
                continue
            }

            let myCallsign = qso.myCallsign.uppercased()
            if !myCallsign.isEmpty,
               let upperPrimary,
               myCallsign != upperPrimary
            {
                presence.uploadRejected = true
                presence.rejectedAtBuild = ServicePresence.currentAppBuild
                result.rejected += 1
                result.modified.append(presence)
                continue
            }

            presence.needsUpload = true
            result.repaired += 1
            result.modified.append(presence)
        }

        return result
    }

    // POTA dead-state recovery is now handled by remote map gap repair
    // (repairPOTAGaps in QSOProcessingActor+POTAGapRepair.swift)
}
