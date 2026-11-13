import CarrierWaveData
import Foundation
import SwiftData

/// Service to detect and repair duplicate QSOs created by two-fer park reference mismatches.
///
/// When QSOs are imported from multiple sources (e.g., PoLo with full ref "US-1044, US-3791"
/// and POTA.app with single ref "US-1044"), duplicates can be created because the park
/// references don't match exactly. This service finds and merges them.
///
/// Detection criteria:
/// - Same callsign (case-insensitive)
/// - Timestamps within 60 seconds (POTA rounds to minutes)
/// - Same band (or one is empty)
/// - Same mode family
/// - One park reference contains the other as a prefix/subset
///
/// Façade over `CrossBatchMerge`. The matcher delegates to `TwoferMatcher` from
/// CarrierWaveCore (UUID-keyed) and translates `[DuplicateGroup]` into a flat
/// list of `(winner, loser)` MergeActions — one per loser, since a single
/// winner can absorb several losers.
actor TwoferDuplicateRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult {
        let duplicateGroupsFound: Int
        let qsosMerged: Int
        let qsosRemoved: Int
    }

    let container: ModelContainer

    /// Count potential duplicate groups (one per winner).
    func countDuplicates() async throws -> Int {
        let plan = try await makeMerge().plan()
        return countWinners(in: plan.actions)
    }

    /// Repair duplicates by merging truncated/single-park versions into full multi-park versions.
    func repairDuplicates() async throws -> RepairResult {
        let merge = makeMerge()
        let plan = try await merge.plan()
        let groupsFound = countWinners(in: plan.actions)
        let result = try await merge.apply(plan)

        return RepairResult(
            duplicateGroupsFound: groupsFound,
            qsosMerged: groupsFound,
            qsosRemoved: result.merged
        )
    }

    // MARK: Private

    /// Snapshot pairs the QSO's persistent identifier with its UUID-keyed snapshot
    /// so the existing TwoferMatcher (UUID-based) can run unchanged.
    private struct Twin {
        let pid: PersistentIdentifier
        let qsoSnapshot: CarrierWaveCore.QSOSnapshot
    }

    /// Run TwoferMatcher on the UUID-side, then translate to PersistentIdentifier actions.
    private static let match: @Sendable ([Twin])
        -> [CrossBatchMerge<QSO, Twin>.MergeAction] = { twins in
            var pidByUUID: [UUID: PersistentIdentifier] = [:]
            var snapshots: [CarrierWaveCore.QSOSnapshot] = []
            snapshots.reserveCapacity(twins.count)
            for twin in twins {
                pidByUUID[twin.qsoSnapshot.id] = twin.pid
                snapshots.append(twin.qsoSnapshot)
            }

            let groups = TwoferMatcher.findTwoferDuplicateGroups(snapshots)
            var actions: [CrossBatchMerge<QSO, Twin>.MergeAction] = []
            for group in groups {
                guard let winnerPid = pidByUUID[group.winnerId] else {
                    continue
                }
                for loserUUID in group.loserIds {
                    guard let loserPid = pidByUUID[loserUUID] else {
                        continue
                    }
                    actions.append(.init(winnerId: winnerPid, loserId: loserPid))
                }
            }
            return actions
        }

    /// Merge: absorb fields, transfer service presence.
    private static let merge: @Sendable (QSO, QSO, ModelContext) -> Void = { winner, loser, _ in
        absorbFields(from: loser, into: winner)
        absorbServicePresence(from: loser, into: winner)
    }

    /// Fill nil/empty fields in winner from loser.
    private static func absorbFields(from loser: QSO, into winner: QSO) {
        winner.rstSent = winner.rstSent ?? loser.rstSent
        winner.rstReceived = winner.rstReceived ?? loser.rstReceived
        winner.myGrid = winner.myGrid ?? loser.myGrid
        winner.theirGrid = winner.theirGrid ?? loser.theirGrid
        winner.notes = winner.notes ?? loser.notes
        winner.qrzLogId = winner.qrzLogId ?? loser.qrzLogId
        winner.rawADIF = winner.rawADIF ?? loser.rawADIF
        winner.frequency = winner.frequency ?? loser.frequency
        winner.name = winner.name ?? loser.name
        winner.qth = winner.qth ?? loser.qth
        winner.state = winner.state ?? loser.state
        winner.country = winner.country ?? loser.country
        winner.power = winner.power ?? loser.power
        winner.myRig = winner.myRig ?? loser.myRig
        winner.theirLicenseClass = winner.theirLicenseClass ?? loser.theirLicenseClass

        let winnerBand = winner.band.trimmingCharacters(in: .whitespaces)
        let loserBand = loser.band.trimmingCharacters(in: .whitespaces)
        if winnerBand.isEmpty, !loserBand.isEmpty {
            winner.band = loser.band
        }
    }

    /// Transfer service presence records from loser to winner.
    private static func absorbServicePresence(from loser: QSO, into winner: QSO) {
        for presence in loser.servicePresence {
            if presence.serviceType == .pota, let parkRef = presence.parkReference {
                if let existing = winner.potaPresence(forPark: parkRef) {
                    if presence.isPresent, !existing.isPresent {
                        existing.isPresent = true
                        existing.needsUpload = false
                        existing.lastConfirmedAt = presence.lastConfirmedAt
                    }
                } else {
                    presence.qso = winner
                    winner.servicePresence.append(presence)
                }
            } else if let existing = winner.presence(for: presence.serviceType) {
                if presence.isPresent, !existing.isPresent {
                    existing.isPresent = true
                    existing.needsUpload = false
                    existing.lastConfirmedAt = presence.lastConfirmedAt
                }
            } else {
                presence.qso = winner
                winner.servicePresence.append(presence)
            }
        }
    }

    private func makeMerge() -> CrossBatchMerge<QSO, Twin> {
        CrossBatchMerge<QSO, Twin>(
            label: "twofer.dedup",
            container: container,
            sortBy: [SortDescriptor(\.timestamp)],
            snapshot: { qso in
                Twin(pid: qso.persistentModelID, qsoSnapshot: qso.toSnapshot())
            },
            match: Self.match,
            merge: Self.merge
        )
    }

    /// Distinct winners across the action list.
    private func countWinners(
        in actions: [CrossBatchMerge<QSO, Twin>.MergeAction]
    ) -> Int {
        Set(actions.map(\.winnerId)).count
    }
}
