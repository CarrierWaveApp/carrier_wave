import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: deduplicate ServicePresence records.
///
/// iCloud sync can create multiple ServicePresence records for the same
/// (QSO, serviceType, parkReference) tuple when records arrive with different
/// UUIDs. This repair keeps the best-status record and deletes the rest.
///
/// Façade over `CrossBatchMerge` with a no-op merge closure — the matcher
/// picks the winner (best by isPresent, isSubmitted, lastConfirmedAt) and
/// the seam deletes each loser.
actor ServicePresenceDeduplicationRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult {
        let scanned: Int
        let deleted: Int
    }

    func repair() async throws -> RepairResult {
        let result = try await CrossBatchMerge<ServicePresence, PresenceSnapshot>(
            label: "servicePresence.dedup",
            container: container,
            snapshot: Self.snapshot,
            match: Self.match,
            merge: { _, _, _ in } // winner already has best fields; just delete loser
        ).run()

        return RepairResult(
            scanned: result.snapshotsCollected,
            deleted: result.merged
        )
    }

    // MARK: Fileprivate

    /// Lightweight snapshot for grouping — avoids holding all ServicePresence objects.
    fileprivate struct PresenceSnapshot {
        let id: PersistentIdentifier
        let qsoId: UUID
        let serviceTypeRaw: String
        let parkReference: String
        let isPresent: Bool
        let isSubmitted: Bool
        let lastConfirmedAt: Date?
    }

    // MARK: Private

    private static let snapshot: @Sendable (ServicePresence) -> PresenceSnapshot? = { presence in
        guard let qsoId = presence.qso?.id else {
            return nil
        }
        return PresenceSnapshot(
            id: presence.persistentModelID,
            qsoId: qsoId,
            serviceTypeRaw: presence.serviceTypeRawValue,
            parkReference: presence.parkReference ?? "",
            isPresent: presence.isPresent,
            isSubmitted: presence.isSubmitted,
            lastConfirmedAt: presence.lastConfirmedAt
        )
    }

    /// Group by (qsoId, serviceType, parkRef); keep the best record, mark the rest as losers.
    private static let match: @Sendable ([PresenceSnapshot])
        -> [CrossBatchMerge<ServicePresence, PresenceSnapshot>.MergeAction] = { snapshots in
            var groups: [String: [PresenceSnapshot]] = [:]
            for snap in snapshots {
                let key = "\(snap.qsoId)|\(snap.serviceTypeRaw)|\(snap.parkReference)"
                groups[key, default: []].append(snap)
            }

            var actions: [CrossBatchMerge<ServicePresence, PresenceSnapshot>.MergeAction] = []
            for records in groups.values where records.count > 1 {
                let sorted = records.sorted { lhs, rhs in
                    if lhs.isPresent != rhs.isPresent {
                        return lhs.isPresent
                    }
                    if lhs.isSubmitted != rhs.isSubmitted {
                        return lhs.isSubmitted
                    }
                    let lDate = lhs.lastConfirmedAt ?? .distantPast
                    let rDate = rhs.lastConfirmedAt ?? .distantPast
                    return lDate > rDate
                }
                let winner = sorted[0]
                for loser in sorted.dropFirst() {
                    actions.append(.init(winnerId: winner.id, loserId: loser.id))
                }
            }
            return actions
        }

    private let container: ModelContainer
}
