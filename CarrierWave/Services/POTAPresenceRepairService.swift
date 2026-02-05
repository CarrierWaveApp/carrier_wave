import CarrierWaveCore
import Foundation
import SwiftData

/// Service to detect and repair incorrectly marked POTA service presence records.
/// Prior to the fix, QSOs without park references were incorrectly marked as needing
/// upload to POTA. This service finds and optionally fixes those records.
///
/// All work happens on a background thread to avoid blocking the UI.
actor POTAPresenceRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult: Sendable {
        let mismarkedCount: Int
        let repairedCount: Int
    }

    let container: ModelContainer

    /// Count QSOs that are incorrectly marked for POTA upload (no park reference but needsUpload=true)
    /// Uses batched fetching to avoid loading all records at once.
    /// Runs on background thread.
    func countMismarkedQSOs() throws -> Int {
        // Create background context for this work
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // SwiftData predicates don't support enum comparisons, so we filter needsUpload
        // at the database level and filter serviceType in memory
        var descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { presence in
                presence.needsUpload
            }
        )

        // Use a reasonable batch size to avoid memory pressure
        let batchSize = 500
        var offset = 0
        var mismarkedCount = 0

        while true {
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = try context.fetch(descriptor)
            if batch.isEmpty {
                break
            }

            for presence in batch {
                // Filter to POTA in memory since predicates don't support enum comparison
                guard presence.serviceType == .pota else {
                    continue
                }
                guard let qso = presence.qso else {
                    continue
                }
                if qso.parkReference?.isEmpty ?? true {
                    mismarkedCount += 1
                }
            }

            offset += batchSize

            // If we got fewer than batch size, we're done
            if batch.count < batchSize {
                break
            }
        }

        return mismarkedCount
    }

    /// Repair mismarked POTA service presence records by setting needsUpload=false
    /// for QSOs that don't have a park reference.
    /// Runs on background thread.
    func repairMismarkedQSOs() throws -> RepairResult {
        // Create background context for this work
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // SwiftData predicates don't support enum comparisons, so we filter needsUpload
        // at the database level and filter serviceType in memory
        var descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { presence in
                presence.needsUpload
            }
        )

        let batchSize = 500
        var offset = 0
        var mismarkedCount = 0
        var repairedCount = 0

        while true {
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = try context.fetch(descriptor)
            if batch.isEmpty {
                break
            }

            for presence in batch {
                // Filter to POTA in memory since predicates don't support enum comparison
                guard presence.serviceType == .pota else {
                    continue
                }
                guard let qso = presence.qso else {
                    continue
                }
                if qso.parkReference?.isEmpty ?? true {
                    mismarkedCount += 1
                    presence.needsUpload = false
                    repairedCount += 1
                }
            }

            offset += batchSize

            if batch.count < batchSize {
                break
            }
        }

        if repairedCount > 0 {
            try context.save()
        }

        return RepairResult(mismarkedCount: mismarkedCount, repairedCount: repairedCount)
    }
}
