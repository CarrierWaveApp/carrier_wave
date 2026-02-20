import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - QSOProcessingActor Orphan Repair

extension QSOProcessingActor {
    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    /// These should never be synced to any service
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Result of DXCC repair operation
    struct DXCCRepairResult: Sendable {
        let repairedCount: Int
        let scannedCount: Int
    }

    /// Result of clearing upload flags on metadata QSOs
    struct MetadataRepairResult: Sendable {
        let clearedCount: Int
    }

    /// Result of clearing upload flags on non-primary callsign QSOs
    struct NonPrimaryCallsignRepairResult: Sendable {
        let clearedCount: Int
        let byCallsign: [String: Int]
    }

    /// Result of clearing upload flags on hidden QSOs
    struct HiddenQSORepairResult: Sendable {
        let clearedCount: Int
    }

    /// Clear needsUpload flags on hidden (soft-deleted) QSOs.
    /// Hidden QSOs should never be synced to any service.
    func clearHiddenQSOUploadFlags(container: ModelContainer) async throws -> HiddenQSORepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch all ServicePresence records that need upload
        let presenceDescriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { $0.needsUpload }
        )
        let presenceRecords = try context.fetch(presenceDescriptor)

        var clearedCount = 0
        var unsavedCount = 0

        for presence in presenceRecords {
            try Task.checkCancellation()

            guard let qso = presence.qso else {
                continue
            }

            if qso.isHidden {
                presence.needsUpload = false
                clearedCount += 1
                unsavedCount += 1

                // Save periodically
                if unsavedCount >= 100 {
                    try context.save()
                    unsavedCount = 0
                }
            }
        }

        // Save any remaining changes
        if unsavedCount > 0 {
            try context.save()
        }

        return HiddenQSORepairResult(clearedCount: clearedCount)
    }

    /// Clear needsUpload flags on metadata pseudo-modes (WEATHER, SOLAR, NOTE).
    /// These are activation metadata from Ham2K PoLo that should never be synced.
    func clearMetadataUploadFlags(container: ModelContainer) async throws -> MetadataRepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch all ServicePresence records that need upload
        let presenceDescriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { $0.needsUpload }
        )
        let presenceRecords = try context.fetch(presenceDescriptor)

        var clearedCount = 0
        var unsavedCount = 0

        for presence in presenceRecords {
            try Task.checkCancellation()

            guard let qso = presence.qso else {
                continue
            }

            // Check if this QSO has a metadata mode
            let mode = qso.mode.uppercased()
            if Self.metadataModes.contains(mode) {
                presence.needsUpload = false
                clearedCount += 1
                unsavedCount += 1

                // Save periodically
                if unsavedCount >= 100 {
                    try context.save()
                    unsavedCount = 0
                }
            }
        }

        // Save any remaining changes
        if unsavedCount > 0 {
            try context.save()
        }

        return MetadataRepairResult(clearedCount: clearedCount)
    }

    /// Clear needsUpload flags on QSOs that don't match the primary callsign.
    /// These QSOs were logged under a previous callsign and will never be uploaded
    /// to services configured with the current callsign.
    func clearNonPrimaryCallsignUploadFlags(
        primaryCallsign: String?,
        container: ModelContainer
    ) async throws -> NonPrimaryCallsignRepairResult {
        // If no primary callsign configured, nothing to do
        guard let primaryCallsign, !primaryCallsign.isEmpty else {
            return NonPrimaryCallsignRepairResult(clearedCount: 0, byCallsign: [:])
        }

        let upperPrimary = primaryCallsign.uppercased()
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch all ServicePresence records that need upload
        let presenceDescriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { $0.needsUpload }
        )
        let presenceRecords = try context.fetch(presenceDescriptor)

        var clearedCount = 0
        var unsavedCount = 0
        var byCallsign: [String: Int] = [:]

        for presence in presenceRecords {
            try Task.checkCancellation()

            guard let qso = presence.qso else {
                continue
            }

            // Check if this QSO's myCallsign matches the primary callsign
            let myCallsign = qso.myCallsign.uppercased()

            // Empty myCallsign is allowed (matches any account)
            // Only clear if there's a non-empty myCallsign that doesn't match primary
            if !myCallsign.isEmpty, myCallsign != upperPrimary {
                presence.needsUpload = false
                clearedCount += 1
                unsavedCount += 1
                byCallsign[myCallsign, default: 0] += 1

                // Save periodically
                if unsavedCount >= 100 {
                    try context.save()
                    unsavedCount = 0
                }
            }
        }

        // Save any remaining changes
        if unsavedCount > 0 {
            try context.save()
        }

        return NonPrimaryCallsignRepairResult(clearedCount: clearedCount, byCallsign: byCallsign)
    }

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

    // MARK: - HAMRS Upload Flag Repair

    /// Result of clearing bogus HAMRS upload flags
    struct HamrsRepairResult: Sendable {
        let clearedCount: Int
    }

    /// Clear needsUpload flags on HAMRS ServicePresence records.
    /// HAMRS does not support uploads but was incorrectly marked as supportsUpload=true,
    /// creating permanent needsUpload=true records that can never be fulfilled.
    func clearBogusHamrsUploadFlags(
        container: ModelContainer
    ) async throws -> HamrsRepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let presenceDescriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { $0.needsUpload }
        )
        let presenceRecords = try context.fetch(presenceDescriptor)

        var clearedCount = 0
        var unsavedCount = 0

        for presence in presenceRecords {
            try Task.checkCancellation()

            if presence.serviceType == .hamrs {
                presence.needsUpload = false
                clearedCount += 1
                unsavedCount += 1

                if unsavedCount >= 100 {
                    try context.save()
                    unsavedCount = 0
                }
            }
        }

        if unsavedCount > 0 {
            try context.save()
        }

        return HamrsRepairResult(clearedCount: clearedCount)
    }

    // MARK: - DXCC Repair

    /// Repair QSOs that have DXCC in rawADIF but not in the dxcc column.
    /// This backfills DXCC data for QSOs imported before the fix was applied.
    func repairMissingDXCC(container: ModelContainer) async throws -> DXCCRepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch QSOs that have rawADIF but no DXCC
        // We can't use a predicate for "rawADIF contains dxcc" so we fetch all without DXCC
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { $0.dxcc == nil && $0.rawADIF != nil }
        )

        let totalCount = (try? context.fetchCount(descriptor)) ?? 0
        if totalCount == 0 {
            return DXCCRepairResult(repairedCount: 0, scannedCount: 0)
        }

        var repairedCount = 0
        var scannedCount = 0
        var unsavedCount = 0
        let batchSize = 500
        var offset = 0

        while offset < totalCount {
            try Task.checkCancellation()

            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = (try? context.fetch(descriptor)) ?? []
            if batch.isEmpty {
                break
            }

            for qso in batch {
                scannedCount += 1

                guard let rawADIF = qso.rawADIF else {
                    continue
                }

                // Extract DXCC from rawADIF using CarrierWaveCore helper
                if let dxcc = ADIFParser.extractDXCC(from: rawADIF) {
                    qso.dxcc = dxcc
                    repairedCount += 1
                    unsavedCount += 1
                }
            }

            // Save periodically
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

        return DXCCRepairResult(repairedCount: repairedCount, scannedCount: scannedCount)
    }
}
