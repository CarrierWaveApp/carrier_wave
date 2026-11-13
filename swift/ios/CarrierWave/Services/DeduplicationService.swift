import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - DeduplicationResult

struct DeduplicationResult {
    let duplicateGroupsFound: Int
    let qsosMerged: Int
    let qsosRemoved: Int
}

// MARK: - DeduplicationService

/// Finds and merges duplicate QSOs.
///
/// Runs on a background actor with batched fetching to avoid loading the
/// entire QSO table into a single ModelContext (which spikes 300+ MB on
/// 100k-QSO databases and OOM-kills iPhone 11).
///
/// Phase 1: Batch-fetch QSOs → lightweight snapshots (~15 MB for 100k).
/// Phase 2: Run dedup matchers on snapshots (UUID + time-window).
/// Phase 3: Fetch only affected QSOs by ID for merge + delete.
actor DeduplicationService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    /// Find and merge duplicate QSOs within the given time window.
    func findAndMergeDuplicates(
        timeWindowMinutes: Int = 5
    ) throws -> DeduplicationResult {
        // Phase 1: Batch-fetch all QSOs into lightweight snapshots.
        // Each batch uses a fresh ModelContext so QSO objects are released.
        let snapshots = fetchAllSnapshots()

        guard !snapshots.isEmpty else {
            return DeduplicationResult(
                duplicateGroupsFound: 0, qsosMerged: 0, qsosRemoved: 0
            )
        }

        // Phase 2a: Find UUID duplicates (iCloud sync corruption).
        let uuidGroups = findUUIDDuplicateGroups(snapshots)

        // Phase 2b: Find time-window duplicates on de-duped snapshot set.
        let uuidLosers = Set(uuidGroups.flatMap(\.loserIds))
        let dedupedSnapshots = snapshots.filter { !uuidLosers.contains($0.id) }

        let config = DeduplicationConfig(
            timeWindowSeconds: TimeInterval(timeWindowMinutes * 60),
            requireBandMatch: true,
            requireParkMatch: true
        )
        let timeGroups = DeduplicationMatcher.findDuplicateGroups(
            dedupedSnapshots, config: config
        )

        // Phase 3: Merge affected QSOs (fresh context, fetches by ID).
        let allGroups = uuidGroups + timeGroups
        guard !allGroups.isEmpty else {
            return DeduplicationResult(
                duplicateGroupsFound: 0, qsosMerged: 0, qsosRemoved: 0
            )
        }

        let (merged, removed) = try mergeGroups(allGroups)

        return DeduplicationResult(
            duplicateGroupsFound: allGroups.count,
            qsosMerged: merged,
            qsosRemoved: removed
        )
    }

    // MARK: Private

    private let container: ModelContainer

    // MARK: - Phase 1: Batched Snapshot Fetch

    private func fetchAllSnapshots() -> [CarrierWaveCore.QSOSnapshot] {
        let batchSize = BoundedDescriptor<QSO>.maxLimit
        var offset = 0
        var snapshots: [CarrierWaveCore.QSOSnapshot] = []

        while true {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<QSO>(
                sortBy: [SortDescriptor(\.timestamp)],
                limit: batchSize,
                offset: offset
            )

            guard let batch = try? context.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }

            for qso in batch {
                snapshots.append(qso.toSnapshot())
            }

            offset += batch.count

            if batch.count < batchSize {
                break
            }
        }

        return snapshots
    }

    // MARK: - Phase 2a: UUID Duplicate Detection

    /// Find QSOs with identical UUIDs (DB corruption from iCloud sync).
    /// Returns groups where the winner has the highest field richness score.
    private func findUUIDDuplicateGroups(
        _ snapshots: [CarrierWaveCore.QSOSnapshot]
    ) -> [DuplicateGroup] {
        var byId: [UUID: [CarrierWaveCore.QSOSnapshot]] = [:]
        for snap in snapshots {
            byId[snap.id, default: []].append(snap)
        }

        var groups: [DuplicateGroup] = []
        for (_, records) in byId where records.count > 1 {
            let sorted = records.sorted { lhs, rhs in
                snapshotRichnessScore(lhs) > snapshotRichnessScore(rhs)
            }
            let winner = sorted[0]
            let losers = sorted.dropFirst().map(\.id)
            groups.append(DuplicateGroup(
                winnerId: winner.id, loserIds: losers
            ))
        }
        return groups
    }

    /// Score snapshot field richness (proxy for service presence + field count).
    private func snapshotRichnessScore(_ snap: CarrierWaveCore.QSOSnapshot) -> Int {
        var score = snap.syncedServicesCount * 100
        let fields: [Any?] = [
            snap.rstSent, snap.rstReceived, snap.myGrid, snap.theirGrid,
            snap.parkReference, snap.notes, snap.rawADIF,
            snap.frequency, snap.name, snap.qth, snap.country, snap.power,
        ]
        score += fields.compactMap { $0 }.count
        return score
    }

    // MARK: - Phase 3: Merge

    /// Fetch only affected QSOs by ID and perform merges.
    private func mergeGroups(
        _ groups: [DuplicateGroup]
    ) throws -> (merged: Int, removed: Int) {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var totalMerged = 0
        var totalRemoved = 0

        for group in groups {
            guard let winner = try fetchQSO(
                id: group.winnerId, context: context
            ) else {
                continue
            }

            for loserId in group.loserIds {
                guard let loser = try fetchQSO(
                    id: loserId, context: context
                ) else {
                    continue
                }

                absorbFields(from: loser, into: winner)
                absorbServicePresence(from: loser, into: winner)
                context.delete(loser)
                totalRemoved += 1
            }
            totalMerged += 1
        }

        if totalRemoved > 0 {
            try context.save()
        }

        return (totalMerged, totalRemoved)
    }

    private func fetchQSO(id: UUID, context: ModelContext) throws -> QSO? {
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.id == id },
            limit: 1
        )
        return try context.boundedFetch(descriptor).first
    }

    /// Fill nil/empty fields in winner from loser
    private func absorbFields(from loser: QSO, into winner: QSO) {
        winner.rstSent = winner.rstSent ?? loser.rstSent
        winner.rstReceived = winner.rstReceived ?? loser.rstReceived
        winner.myGrid = winner.myGrid ?? loser.myGrid
        winner.theirGrid = winner.theirGrid ?? loser.theirGrid
        winner.parkReference = winner.parkReference ?? loser.parkReference
        winner.notes = winner.notes ?? loser.notes
        winner.qrzLogId = winner.qrzLogId ?? loser.qrzLogId
        winner.rawADIF = winner.rawADIF ?? loser.rawADIF
        winner.frequency = winner.frequency ?? loser.frequency
        // Absorb band if winner has empty band (e.g., from POTA)
        let winnerBand = winner.band.trimmingCharacters(in: .whitespaces)
        let loserBand = loser.band.trimmingCharacters(in: .whitespaces)
        if winnerBand.isEmpty, !loserBand.isEmpty {
            winner.band = loser.band
        }
        // Prefer specific mode over generic (e.g., SSB over PHONE)
        winner.mode = ModeEquivalence.moreSpecific(winner.mode, loser.mode)
    }

    /// Transfer service presence records from loser to winner
    private func absorbServicePresence(from loser: QSO, into winner: QSO) {
        for presence in loser.servicePresence {
            if let existing = winner.presence(for: presence.serviceType) {
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
}

// MARK: - QSO Extension for Snapshot Conversion

extension QSO {
    /// Convert QSO to a CarrierWaveCore QSOSnapshot for deduplication
    nonisolated func toSnapshot() -> CarrierWaveCore.QSOSnapshot {
        CarrierWaveCore.QSOSnapshot(
            id: id,
            callsign: callsign,
            timestamp: timestamp,
            band: band,
            mode: mode,
            parkReference: parkReference,
            frequency: frequency,
            rstSent: rstSent,
            rstReceived: rstReceived,
            myGrid: myGrid,
            theirGrid: theirGrid,
            notes: notes,
            rawADIF: rawADIF,
            name: name,
            qth: qth,
            state: state,
            country: country,
            power: power,
            theirLicenseClass: theirLicenseClass,
            satName: satName,
            propMode: propMode,
            syncedServicesCount: syncedServicesCount
        )
    }
}
