import CarrierWaveData
import Foundation
import SwiftData

// MARK: - Dead State Repair (QRZ + POTA)

extension QSOProcessingActor {
    // MARK: - QRZ Dead State Repair

    /// Result of repairing QRZ dead-state QSOs
    struct QRZDeadStateRepairResult: Sendable {
        let repairedCount: Int
    }

    /// Repair QRZ ServicePresence records stuck in dead state.
    /// Dead state: isPresent=false, needsUpload=false, isSubmitted=false, uploadRejected=false.
    /// This happens when uploadToQRZ clears needsUpload but QRZ download never confirms the QSO.
    func repairQRZDeadStateQSOs(
        container: ModelContainer
    ) async throws -> QRZDeadStateRepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch all QRZ ServicePresence records in dead state
        // Can't filter by serviceType in predicate, so fetch all non-present,
        // non-needsUpload records and filter in memory
        let descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> {
                !$0.isPresent && !$0.needsUpload && !$0.isSubmitted && !$0.uploadRejected
            }
        )
        let records = try context.fetch(descriptor)

        var repairedCount = 0
        var unsavedCount = 0

        for presence in records {
            try Task.checkCancellation()

            guard presence.serviceType == .qrz else {
                continue
            }
            guard let qso = presence.qso, !qso.isHidden else {
                continue
            }

            presence.needsUpload = true
            repairedCount += 1
            unsavedCount += 1

            if unsavedCount >= 100 {
                try context.save()
                unsavedCount = 0
            }
        }

        if unsavedCount > 0 {
            try context.save()
        }

        return QRZDeadStateRepairResult(repairedCount: repairedCount)
    }

    // POTA dead-state recovery is now handled by remote map gap repair
    // (repairPOTAGaps in QSOProcessingActor+POTAGapRepair.swift)
}
