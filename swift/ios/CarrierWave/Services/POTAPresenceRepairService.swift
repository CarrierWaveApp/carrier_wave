import CarrierWaveData
import Foundation
import SwiftData

/// Service to detect and repair incorrectly marked POTA service presence records.
/// Prior to the fix, QSOs without park references were incorrectly marked as needing
/// upload to POTA. This service finds and optionally fixes those records.
///
/// Façade over `BatchedRewrite`. Predicates can't compare enums, so the closure
/// filters serviceType in memory.
actor POTAPresenceRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult {
        let mismarkedCount: Int
        let repairedCount: Int
    }

    let container: ModelContainer

    /// Count QSOs that are incorrectly marked for POTA upload (no park reference but needsUpload=true).
    func countMismarkedQSOs() async throws -> Int {
        let counter = Counter()
        _ = try await BatchedRewrite<ServicePresence>(
            label: "potaPresence.count",
            container: container,
            predicate: #Predicate<ServicePresence> { $0.needsUpload }
        ) { presence, _ in
            if Self.isMismarked(presence) {
                counter.value += 1
            }
            return false // never mutates — count-only
        }.run()
        return counter.value
    }

    /// Repair mismarked POTA service presence records by setting needsUpload=false
    /// for QSOs that don't have a park reference.
    func repairMismarkedQSOs() async throws -> RepairResult {
        let counter = Counter()
        let result = try await BatchedRewrite<ServicePresence>(
            label: "potaPresence.repair",
            container: container,
            predicate: #Predicate<ServicePresence> { $0.needsUpload },
            mutate: { presence, _ in
                guard Self.isMismarked(presence) else {
                    return false
                }
                counter.value += 1
                presence.needsUpload = false
                return true
            },
            // Route the off-main save through the seam: cw-store first in `.on`,
            // then a per-context-suppressed save (presence-only, no QSO co-mutation).
            commit: { presences, context in
                try OffMainStoreSeam.commitPresence(presences, in: context)
            }
        ).run()

        return RepairResult(
            mismarkedCount: counter.value,
            repairedCount: result.mutated
        )
    }

    // MARK: Private

    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    private static func isMismarked(_ presence: ServicePresence) -> Bool {
        guard presence.serviceType == .pota else {
            return false
        }
        guard let qso = presence.qso else {
            return false
        }
        return qso.parkReference?.isEmpty ?? true
    }
}
