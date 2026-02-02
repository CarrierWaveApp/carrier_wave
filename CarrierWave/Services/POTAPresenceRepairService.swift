import Foundation
import SwiftData

/// Service to detect and repair incorrectly marked POTA service presence records.
/// Prior to the fix, QSOs without park references were incorrectly marked as needing
/// upload to POTA. This service finds and optionally fixes those records.
@MainActor
class POTAPresenceRepairService {
    // MARK: Lifecycle

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: Internal

    struct RepairResult {
        let mismarkedCount: Int
        let repairedCount: Int
    }

    let modelContext: ModelContext

    /// Count QSOs that are incorrectly marked for POTA upload (no park reference but needsUpload=true)
    /// Uses batched fetching to avoid loading all records at once.
    func countMismarkedQSOs() throws -> Int {
        // First, get just the POTA presence records that need upload
        // This filters at the database level to avoid loading all ServicePresence records
        let potaService = ServiceType.pota
        var descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { presence in
                presence.serviceType == potaService && presence.needsUpload
            }
        )

        // Use a reasonable batch size to avoid memory pressure
        let batchSize = 500
        var offset = 0
        var mismarkedCount = 0

        while true {
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = try modelContext.fetch(descriptor)
            if batch.isEmpty {
                break
            }

            for presence in batch {
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
    func repairMismarkedQSOs() throws -> RepairResult {
        // Filter to only POTA presence records that need upload
        let potaService = ServiceType.pota
        var descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { presence in
                presence.serviceType == potaService && presence.needsUpload
            }
        )

        let batchSize = 500
        var offset = 0
        var mismarkedCount = 0
        var repairedCount = 0

        while true {
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = try modelContext.fetch(descriptor)
            if batch.isEmpty {
                break
            }

            for presence in batch {
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
            try modelContext.save()
        }

        return RepairResult(mismarkedCount: mismarkedCount, repairedCount: repairedCount)
    }
}
