import Foundation
import SwiftData

// MARK: - QSOProcessingActor Orphan Repair

extension QSOProcessingActor {
    /// Snapshot of an orphaned QSO for logging purposes.
    struct OrphanedQSOInfo: Sendable {
        let callsign: String
        let band: String
        let mode: String
        let timestamp: Date
        let myCallsign: String
        let missingServices: [ServiceType]
    }

    /// Result of orphan repair operation.
    struct OrphanRepairResult: Sendable {
        let orphanedQSOs: [OrphanedQSOInfo]
        let repairedCount: Int
    }

    /// Result of processing a batch of QSOs for orphan repair.
    private struct BatchResult {
        var orphaned: [OrphanedQSOInfo] = []
        var repairedCount = 0
        var unsavedCount = 0
    }

    /// Detect and repair QSOs that are missing ServicePresence records for configured services.
    /// Creates ServicePresence records with needsUpload=true for missing services.
    /// Returns info about orphaned QSOs for logging.
    func repairOrphanedQSOs(
        for services: Set<ServiceType>,
        userCallsigns: Set<String>,
        container: ModelContainer
    ) async throws -> OrphanRepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var orphaned: [OrphanedQSOInfo] = []
        var repairedCount = 0

        // Fetch all non-hidden QSOs in batches
        let countDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { !$0.isHidden }
        )
        let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0

        if totalCount == 0 {
            return OrphanRepairResult(orphanedQSOs: [], repairedCount: 0)
        }

        let batchSize = 500
        var offset = 0
        var unsavedCount = 0

        while offset < totalCount {
            try Task.checkCancellation()

            let batchResult = try processOrphanBatch(
                context: context,
                services: services,
                userCallsigns: userCallsigns,
                offset: offset,
                batchSize: batchSize
            )

            orphaned.append(contentsOf: batchResult.orphaned)
            repairedCount += batchResult.repairedCount
            unsavedCount += batchResult.unsavedCount

            // Save periodically to avoid huge transactions
            if unsavedCount >= 100 {
                try context.save()
                unsavedCount = 0
            }

            offset += batchSize
            await Task.yield()
        }

        // Save any remaining changes
        if unsavedCount > 0 {
            try context.save()
        }

        return OrphanRepairResult(orphanedQSOs: orphaned, repairedCount: repairedCount)
    }

    /// Process a single batch of QSOs for orphan detection and repair.
    private func processOrphanBatch(
        context: ModelContext,
        services: Set<ServiceType>,
        userCallsigns: Set<String>,
        offset: Int,
        batchSize: Int
    ) throws -> BatchResult {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { !$0.isHidden }
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = batchSize

        let batch = (try? context.fetch(descriptor)) ?? []

        var result = BatchResult()

        for qso in batch {
            // Only check QSOs that belong to the user (match one of their callsigns)
            let myCallsign = qso.myCallsign.uppercased()
            guard userCallsigns.isEmpty || userCallsigns.contains(myCallsign) else {
                continue
            }

            if let orphanInfo = repairQSOIfOrphaned(qso: qso, services: services, context: context) {
                result.orphaned.append(orphanInfo.info)
                result.repairedCount += orphanInfo.repairedCount
                result.unsavedCount += orphanInfo.repairedCount
            }
        }

        return result
    }

    /// Check a single QSO for missing services and repair if needed.
    /// Returns nil if no services are missing.
    private func repairQSOIfOrphaned(
        qso: QSO,
        services: Set<ServiceType>,
        context: ModelContext
    ) -> (info: OrphanedQSOInfo, repairedCount: Int)? {
        var missingServices: [ServiceType] = []
        var repairedCount = 0

        for service in services {
            // Skip POTA for non-activation QSOs
            if service == .pota, qso.parkReference?.isEmpty ?? true {
                continue
            }

            let hasPresence = qso.servicePresence.contains { $0.serviceType == service }
            if !hasPresence {
                missingServices.append(service)

                // Create the missing ServicePresence record
                let presence = ServicePresence(
                    serviceType: service,
                    isPresent: false,
                    needsUpload: service.supportsUpload,
                    qso: qso
                )
                context.insert(presence)
                qso.servicePresence.append(presence)
                repairedCount += 1
            }
        }

        guard !missingServices.isEmpty else {
            return nil
        }

        let orphanInfo = OrphanedQSOInfo(
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            timestamp: qso.timestamp,
            myCallsign: qso.myCallsign,
            missingServices: missingServices
        )

        return (orphanInfo, repairedCount)
    }
}
