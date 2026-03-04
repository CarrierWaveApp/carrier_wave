import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: mark existing activity log QSOs with isActivityLogQSO=true
/// and fix any that incorrectly had parkReference set (should be theirParkReference
/// for hunter QSOs). Activity log QSOs are identified by having a loggingSessionId
/// that matches an ActivityLog record.
actor ActivityLogQSORepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult: Sendable {
        let flagged: Int
        let parkRefsMoved: Int
    }

    let container: ModelContainer

    /// Run the repair. Returns counts of QSOs flagged and park refs moved.
    func repair() throws -> RepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Step 1: Fetch all ActivityLog IDs
        let logDescriptor = FetchDescriptor<ActivityLog>()
        let allLogs = try context.fetch(logDescriptor)
        let logIds = Set(allLogs.map(\.id))

        guard !logIds.isEmpty else {
            return RepairResult(flagged: 0, parkRefsMoved: 0)
        }

        // Step 2: Find QSOs not yet flagged that belong to activity logs
        var flagged = 0
        var parkRefsMoved = 0
        let batchSize = 500

        // Fetch QSOs that have a loggingSessionId and aren't yet flagged
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate<QSO> { qso in
                    !qso.isActivityLogQSO && qso.loggingSessionId != nil
                }
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset

            let candidates = try context.fetch(descriptor)
            if candidates.isEmpty {
                break
            }

            for qso in candidates {
                guard let sessionId = qso.loggingSessionId,
                      logIds.contains(sessionId)
                else {
                    continue
                }

                qso.isActivityLogQSO = true
                flagged += 1

                // If parkReference was set but theirParkReference is empty,
                // move the value — it's the hunted park, not the operator's park
                if let parkRef = qso.parkReference, !parkRef.isEmpty {
                    if qso.theirParkReference == nil || (qso.theirParkReference ?? "").isEmpty {
                        qso.theirParkReference = parkRef
                    }
                    qso.parkReference = nil
                    parkRefsMoved += 1
                }
            }

            if candidates.count < batchSize {
                break
            }
            offset += batchSize
        }

        if flagged > 0 {
            try context.save()
        }

        return RepairResult(flagged: flagged, parkRefsMoved: parkRefsMoved)
    }
}
