import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair service to detect and merge duplicate QSOs caused by phone-family
/// mode mismatches (e.g., PHONE vs SSB, USB vs SSB) between different sync services.
///
/// Detection criteria:
/// - Same callsign (case-insensitive)
/// - Same band
/// - Timestamps within 120 seconds (2-minute dedup window)
/// - Both modes are in the phone family but differ (e.g., USB vs SSB, PHONE vs SSB)
///
/// Merge strategy:
/// - Prefer QSO with more service presence data (richer sync state)
/// - Absorb fields and service presence from loser into winner
/// - Keep the more specific mode (e.g., USB over SSB, SSB over PHONE)
/// - Delete the loser after merge
///
/// Implementation note: this is a façade over `CrossBatchMerge`. The matcher
/// owns the (callsign, band, timestamp-bucket) grouping and chooses the winner
/// by sync presence; the merge closure handles field absorption, service
/// presence transfer, and mode promotion.
actor PhoneSSBDuplicateRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult {
        let duplicatesFound: Int
        let qsosMerged: Int
    }

    let container: ModelContainer

    /// Count potential PHONE/SSB duplicate pairs (dry run — does not mutate).
    func countDuplicates() async throws -> Int {
        try await makeMerge().plan().actions.count
    }

    /// Repair duplicates by merging PHONE/SSB pairs.
    func repairDuplicates() async throws -> RepairResult {
        let result = try await makeMerge().run()
        return RepairResult(
            duplicatesFound: result.pairsFound,
            qsosMerged: result.merged
        )
    }

    // MARK: Private

    /// Lightweight snapshot for PHONE/SSB matching (avoids holding QSO objects).
    private struct PhoneSSBSnapshot {
        let id: PersistentIdentifier
        let callsign: String
        let band: String
        let mode: String
        let timestamp: Date
        let syncedServicesCount: Int
    }

    private static let targetModes = ModeEquivalence.phoneModes

    /// Extract a snapshot only for phone-family rows; everything else is skipped.
    private static let snapshot: @Sendable (QSO) -> PhoneSSBSnapshot? = { qso in
        guard targetModes.contains(qso.mode.uppercased()) else {
            return nil
        }
        return PhoneSSBSnapshot(
            id: qso.persistentModelID,
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            timestamp: qso.timestamp,
            syncedServicesCount: qso.syncedServicesCount
        )
    }

    /// Group by (callsign, band, 120s bucket); within each group, greedily pair
    /// rows whose modes differ. Winner = more sync presence.
    private static let match: @Sendable ([PhoneSSBSnapshot])
        -> [CrossBatchMerge<QSO, PhoneSSBSnapshot>.MergeAction] = { snapshots in
            var groups: [String: [PhoneSSBSnapshot]] = [:]
            for snap in snapshots {
                let bucket = Int(snap.timestamp.timeIntervalSince1970 / 120) * 120
                let key = "\(snap.callsign.uppercased())|\(snap.band.uppercased())|\(bucket)"
                groups[key, default: []].append(snap)
            }

            var actions: [CrossBatchMerge<QSO, PhoneSSBSnapshot>.MergeAction] = []
            for group in groups.values {
                actions.append(contentsOf: pairsWithinGroup(group))
            }
            return actions
        }

    /// Merge: absorb fields, transfer service presence, promote mode.
    private static let merge: @Sendable (QSO, QSO, ModelContext) -> Void = { winner, loser, _ in
        absorbFields(from: loser, into: winner)
        absorbServicePresence(from: loser, into: winner)
        winner.mode = ModeEquivalence.moreSpecific(winner.mode, loser.mode)
    }

    private static func pairsWithinGroup(
        _ group: [PhoneSSBSnapshot]
    ) -> [CrossBatchMerge<QSO, PhoneSSBSnapshot>.MergeAction] {
        guard group.count >= 2 else {
            return []
        }
        let modes = Set(group.map { $0.mode.uppercased() })
        guard modes.count >= 2 else {
            return []
        }

        let sorted = group.sorted { $0.syncedServicesCount > $1.syncedServicesCount }
        var matched = Set<PersistentIdentifier>()
        var pairs: [CrossBatchMerge<QSO, PhoneSSBSnapshot>.MergeAction] = []

        for (idx, snap) in sorted.enumerated() {
            guard !matched.contains(snap.id) else {
                continue
            }
            for other in sorted[(idx + 1)...] {
                guard !matched.contains(other.id),
                      snap.mode.uppercased() != other.mode.uppercased()
                else {
                    continue
                }
                let timeDiff = abs(snap.timestamp.timeIntervalSince(other.timestamp))
                guard timeDiff <= 120 else {
                    continue
                }

                matched.insert(snap.id)
                matched.insert(other.id)
                pairs.append(.init(winnerId: snap.id, loserId: other.id))
                break
            }
        }
        return pairs
    }

    /// Fill nil/empty fields in winner from loser
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
        winner.sotaRef = winner.sotaRef ?? loser.sotaRef

        winner.parkReference = FetchedQSO.combineParkReferences(
            winner.parkReference, loser.parkReference
        )
        winner.theirParkReference = FetchedQSO.combineParkReferences(
            winner.theirParkReference, loser.theirParkReference
        )

        let winnerBand = winner.band.trimmingCharacters(in: .whitespaces)
        let loserBand = loser.band.trimmingCharacters(in: .whitespaces)
        if winnerBand.isEmpty, !loserBand.isEmpty {
            winner.band = loser.band
        }

        if loser.qrzConfirmed {
            winner.qrzConfirmed = true
        }
        if loser.lotwConfirmed {
            winner.lotwConfirmed = true
        }
        winner.lotwConfirmedDate = winner.lotwConfirmedDate ?? loser.lotwConfirmedDate
        winner.dxcc = winner.dxcc ?? loser.dxcc
    }

    /// Transfer service presence records from loser to winner
    private static func absorbServicePresence(from loser: QSO, into winner: QSO) {
        for presence in loser.servicePresence where !presence.isDeleted {
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

    private func makeMerge() -> CrossBatchMerge<QSO, PhoneSSBSnapshot> {
        CrossBatchMerge<QSO, PhoneSSBSnapshot>(
            label: "phoneSSB.dedup",
            container: container,
            predicate: #Predicate<QSO> { !$0.isHidden },
            sortBy: [SortDescriptor(\.timestamp)],
            snapshot: Self.snapshot,
            match: Self.match,
            merge: Self.merge
        )
    }
}
