import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QSOProcessingActor Orphan Repair

extension QSOProcessingActor {
    /// Result of DXCC repair operation
    struct DXCCRepairResult {
        let repairedCount: Int
        let scannedCount: Int
    }

    /// Result of clearing upload flags on metadata QSOs
    struct MetadataRepairResult {
        let clearedCount: Int
        let byService: [ServiceType: Int]
    }

    /// Result of clearing upload flags on non-primary callsign QSOs
    struct NonPrimaryCallsignRepairResult {
        let clearedCount: Int
        let byCallsign: [String: Int]
    }

    /// Result of clearing upload flags on hidden QSOs
    struct HiddenQSORepairResult {
        let clearedCount: Int
    }

    /// Clear needsUpload flags on hidden (soft-deleted) QSOs.
    /// Hidden QSOs should never be synced to any service.
    /// Uses batched fetching with fresh contexts to cap memory usage.
    func clearHiddenQSOUploadFlags(container: ModelContainer) async throws -> HiddenQSORepairResult {
        var clearedCount = 0
        let batchSize = 500
        var offset = 0

        while true {
            try Task.checkCancellation()
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate<ServicePresence> { $0.needsUpload },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            var batchCleared = 0
            for presence in batch {
                guard let qso = presence.qso, !qso.isDeleted, qso.isHidden else {
                    continue
                }
                presence.needsUpload = false
                batchCleared += 1
            }

            if batchCleared > 0 {
                try context.save()
            }
            clearedCount += batchCleared
            // Modified records drop out of needsUpload predicate after save
            offset += batch.count - batchCleared
            await Task.yield()
        }

        return HiddenQSORepairResult(clearedCount: clearedCount)
    }

    /// Clear needsUpload flags on PoLo metadata pseudo-modes (`QSOMode.metadataModes`).
    /// These are activation markers from Ham2K PoLo that must never be synced.
    /// Delegates to `MetadataUploadFlagRepairService` (CAR-278) so the per-sync pass
    /// and the one-time launch repair share one implementation.
    func clearMetadataUploadFlags(container: ModelContainer) async throws -> MetadataRepairResult {
        let result = try await MetadataUploadFlagRepairService(container: container).repair()
        return MetadataRepairResult(clearedCount: result.clearedCount, byService: result.byService)
    }

    /// Clear needsUpload flags on QSOs that don't match the primary callsign.
    /// These QSOs were logged under a previous callsign and will never be uploaded
    /// to services configured with the current callsign.
    /// Uses batched fetching with fresh contexts to cap memory usage.
    func clearNonPrimaryCallsignUploadFlags(
        primaryCallsign: String?,
        container: ModelContainer
    ) async throws -> NonPrimaryCallsignRepairResult {
        guard let primaryCallsign, !primaryCallsign.isEmpty else {
            return NonPrimaryCallsignRepairResult(clearedCount: 0, byCallsign: [:])
        }

        let upperPrimary = primaryCallsign.uppercased()
        var clearedCount = 0
        var byCallsign: [String: Int] = [:]
        let batchSize = 500
        var offset = 0

        while true {
            try Task.checkCancellation()
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate<ServicePresence> { $0.needsUpload },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            var batchCleared = 0
            for presence in batch {
                guard let qso = presence.qso, !qso.isDeleted else {
                    continue
                }
                let myCallsign = qso.myCallsign.uppercased()
                if !myCallsign.isEmpty, myCallsign != upperPrimary {
                    presence.needsUpload = false
                    batchCleared += 1
                    byCallsign[myCallsign, default: 0] += 1
                }
            }

            if batchCleared > 0 {
                try context.save()
            }
            clearedCount += batchCleared
            offset += batch.count - batchCleared
            await Task.yield()
        }

        return NonPrimaryCallsignRepairResult(clearedCount: clearedCount, byCallsign: byCallsign)
    }

    /// Snapshot of an orphaned QSO for logging purposes.
    struct OrphanedQSOInfo {
        let callsign: String
        let band: String
        let mode: String
        let timestamp: Date
        let myCallsign: String
        let missingServices: [ServiceType]
    }

    /// Result of orphan repair operation.
    struct OrphanRepairResult {
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
    /// Uses fresh contexts per batch to cap memory usage.
    func repairOrphanedQSOs(
        for services: Set<ServiceType>,
        userCallsigns: Set<String>,
        container: ModelContainer
    ) async throws -> OrphanRepairResult {
        var orphaned: [OrphanedQSOInfo] = []
        var repairedCount = 0

        let countContext = ModelContext(container)
        let totalCount = (try? countContext.boundedCount(
            QSO.self,
            predicate: #Predicate<QSO> { !$0.isHidden }
        )) ?? 0

        if totalCount == 0 {
            return OrphanRepairResult(orphanedQSOs: [], repairedCount: 0)
        }

        let batchSize = 500
        var offset = 0

        while offset < totalCount {
            try Task.checkCancellation()
            let batchResult = try processOrphanBatch(
                container: container, services: services,
                userCallsigns: userCallsigns, offset: offset, batchSize: batchSize
            )
            orphaned.append(contentsOf: batchResult.orphaned)
            repairedCount += batchResult.repairedCount
            offset += batchSize
            await Task.yield()
        }

        return OrphanRepairResult(orphanedQSOs: orphaned, repairedCount: repairedCount)
    }

    /// Process a single batch of QSOs for orphan detection and repair.
    /// Creates a fresh context to avoid accumulating model objects across batches.
    private func processOrphanBatch(
        container: ModelContainer,
        services: Set<ServiceType>,
        userCallsigns: Set<String>,
        offset: Int,
        batchSize: Int
    ) throws -> BatchResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { !$0.isHidden },
            limit: batchSize,
            offset: offset
        )

        let batch = (try? context.boundedFetch(descriptor)) ?? []
        var result = BatchResult()

        for qso in batch {
            guard !qso.isDeleted else {
                continue
            }
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

        if result.unsavedCount > 0 {
            try context.save()
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

                // Create the missing ServicePresence record. PoLo marker rows
                // (CAR-278) get a presence row so they stop reading as orphaned,
                // but it must never be pending — nothing will ever upload them.
                let presence = ServicePresence(
                    serviceType: service,
                    isPresent: false,
                    needsUpload: service.supportsUpload && !QSOMode.isMetadata(qso.mode),
                    qso: qso
                )
                presence.cloudDirtyFlag = true
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

    // MARK: - HAMRS Upload Flag Repair

    /// Result of clearing bogus HAMRS upload flags
    struct HamrsRepairResult {
        let clearedCount: Int
    }

    /// Clear needsUpload flags on HAMRS ServicePresence records.
    /// HAMRS does not support uploads but was incorrectly marked as supportsUpload=true,
    /// creating permanent needsUpload=true records that can never be fulfilled.
    /// Uses batched fetching with fresh contexts to cap memory usage.
    func clearBogusHamrsUploadFlags(
        container: ModelContainer
    ) async throws -> HamrsRepairResult {
        var clearedCount = 0
        let batchSize = 500
        var offset = 0

        while true {
            try Task.checkCancellation()
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate<ServicePresence> { $0.needsUpload },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            var batchCleared = 0
            for presence in batch where presence.serviceType == .hamrs {
                presence.needsUpload = false
                batchCleared += 1
            }

            if batchCleared > 0 {
                try context.save()
            }
            clearedCount += batchCleared
            offset += batch.count - batchCleared
            await Task.yield()
        }

        return HamrsRepairResult(clearedCount: clearedCount)
    }

    // MARK: - Unconfigured Service Repair

    struct UnconfiguredServiceRepairResult {
        let clearedCount: Int
        let byService: [ServiceType: Int]
    }

    /// Clear needsUpload flags on ServicePresence records for services that aren't configured.
    /// Prevents phantom pending upload counts for services the user hasn't set up.
    func clearUnconfiguredServiceUploadFlags(
        configuredServices: Set<ServiceType>,
        container: ModelContainer
    ) async throws -> UnconfiguredServiceRepairResult {
        var clearedCount = 0
        var byService: [ServiceType: Int] = [:]
        let batchSize = 500
        var offset = 0

        while true {
            try Task.checkCancellation()
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate<ServicePresence> { $0.needsUpload },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            var batchCleared = 0
            for presence in batch {
                let service = presence.serviceType
                if service.supportsUpload, !configuredServices.contains(service) {
                    presence.needsUpload = false
                    batchCleared += 1
                    byService[service, default: 0] += 1
                }
            }

            if batchCleared > 0 {
                try context.save()
            }
            clearedCount += batchCleared
            offset += batch.count - batchCleared
            await Task.yield()
        }

        return UnconfiguredServiceRepairResult(
            clearedCount: clearedCount, byService: byService
        )
    }

    // MARK: - DXCC Repair

    /// Repair QSOs that have DXCC in rawADIF but not in the dxcc column.
    /// This backfills DXCC data for QSOs imported before the fix was applied.
    /// Uses fresh contexts per batch to cap memory usage.
    func repairMissingDXCC(container: ModelContainer) async throws -> DXCCRepairResult {
        let countContext = ModelContext(container)
        let totalCount = (try? countContext.boundedCount(
            QSO.self,
            predicate: #Predicate<QSO> { $0.dxcc == nil && $0.rawADIF != nil }
        )) ?? 0
        if totalCount == 0 {
            return DXCCRepairResult(repairedCount: 0, scannedCount: 0)
        }

        var repairedCount = 0
        var scannedCount = 0
        let batchSize = 500
        var offset = 0

        while offset < totalCount {
            try Task.checkCancellation()

            // Fresh context per batch to release model objects between iterations
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate<QSO> { $0.dxcc == nil && $0.rawADIF != nil },
                limit: batchSize,
                offset: offset
            )

            let batch = (try? context.boundedFetch(descriptor)) ?? []
            if batch.isEmpty {
                break
            }

            var batchRepaired = 0
            for qso in batch {
                scannedCount += 1
                guard let rawADIF = qso.rawADIF else {
                    continue
                }
                if let dxcc = ADIFParser.extractDXCC(from: rawADIF) {
                    qso.dxcc = dxcc
                    batchRepaired += 1
                }
            }

            if batchRepaired > 0 {
                try context.save()
            }
            repairedCount += batchRepaired
            // Repaired records drop out of predicate (dxcc != nil), adjust offset
            offset += batch.count - batchRepaired
            await Task.yield()
        }

        return DXCCRepairResult(repairedCount: repairedCount, scannedCount: scannedCount)
    }
}
