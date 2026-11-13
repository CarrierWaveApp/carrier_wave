import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: mark existing activity log QSOs with isActivityLogQSO=true
/// and fix any that incorrectly had parkReference set (should be theirParkReference
/// for hunter QSOs). Activity log QSOs are identified by having a loggingSessionId
/// that matches an ActivityLog record.
///
/// Façade over `BatchedRewrite`. The ActivityLog ID set is fetched once and
/// captured in the per-row closure for O(1) membership checks.
actor ActivityLogQSORepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult {
        let flagged: Int
        let parkRefsMoved: Int
    }

    let container: ModelContainer

    /// Run the repair. Returns counts of QSOs flagged and park refs moved.
    func repair() async throws -> RepairResult {
        let logIds = try fetchLogIds()
        guard !logIds.isEmpty else {
            return RepairResult(flagged: 0, parkRefsMoved: 0)
        }

        // Counters captured by the closure. The underlying actor invokes the
        // closure on its isolation domain so a class-based wrapper is fine.
        let counters = Counters()

        let result = try await BatchedRewrite<QSO>(
            label: "activityLogQSO.repair",
            container: container,
            predicate: #Predicate<QSO> { qso in
                !qso.isActivityLogQSO && qso.loggingSessionId != nil
            }
        ) { qso, _ in
            guard let sessionId = qso.loggingSessionId,
                  logIds.contains(sessionId)
            else {
                return false
            }
            qso.isActivityLogQSO = true

            if let parkRef = qso.parkReference, !parkRef.isEmpty {
                if qso.theirParkReference == nil || (qso.theirParkReference ?? "").isEmpty {
                    qso.theirParkReference = parkRef
                }
                qso.parkReference = nil
                counters.parkRefsMoved += 1
            }
            return true
        }.run()

        return RepairResult(flagged: result.mutated, parkRefsMoved: counters.parkRefsMoved)
    }

    // MARK: Private

    /// Mutable counter for side-effects the standard `Result` doesn't carry.
    /// Marked `@unchecked Sendable` because the BatchedRewrite actor serialises
    /// closure calls onto its own executor.
    private final class Counters: @unchecked Sendable {
        var parkRefsMoved = 0
    }

    private func fetchLogIds() throws -> Set<UUID> {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let logs = try context.fetch(FetchDescriptor<ActivityLog>())
        return Set(logs.map(\.id))
    }
}
