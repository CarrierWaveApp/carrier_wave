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
/// Merge strategy:
/// - Keep the QSO with the most complete park reference
/// - Absorb service presence records from the duplicate
/// - Delete the duplicate after merge
actor TwoferDuplicateRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult: Sendable {
        let duplicateGroupsFound: Int
        let qsosMerged: Int
        let qsosRemoved: Int
    }

    let container: ModelContainer

    /// Count potential duplicate groups
    func countDuplicates() throws -> Int {
        let groups = try findDuplicateGroups()
        return groups.count
    }

    /// Repair duplicates by merging truncated/single-park versions into full multi-park versions
    func repairDuplicates() throws -> RepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let groups = try findDuplicateGroups()
        var totalMerged = 0
        var totalRemoved = 0

        for group in groups {
            // Fetch the actual QSO objects
            guard let winner = try fetchQSO(id: group.winnerId, context: context) else {
                continue
            }

            for loserId in group.loserIds {
                guard let loser = try fetchQSO(id: loserId, context: context) else {
                    continue
                }

                // Absorb fields and service presence from loser into winner
                absorbFields(from: loser, into: winner)
                absorbServicePresence(from: loser, into: winner)

                // Delete the loser
                context.delete(loser)
                totalRemoved += 1
            }

            totalMerged += 1
        }

        if totalRemoved > 0 {
            try context.save()
        }

        return RepairResult(
            duplicateGroupsFound: groups.count,
            qsosMerged: totalMerged,
            qsosRemoved: totalRemoved
        )
    }

    // MARK: Private

    /// Find all duplicate groups by scanning QSOs with multi-park references
    /// Uses CarrierWaveCore's TwoferMatcher for the pure matching logic
    private func findDuplicateGroups() throws -> [DuplicateGroup] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch all QSOs with park references
        let descriptor = FetchDescriptor<QSO>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let allQSOs = try context.fetch(descriptor)

        // Convert to sendable snapshots
        let allSnapshots = allQSOs.map { $0.toSnapshot() }

        // Use CarrierWaveCore's two-fer matcher
        return TwoferMatcher.findTwoferDuplicateGroups(allSnapshots)
    }

    /// Fetch a QSO by ID
    private func fetchQSO(id: UUID, context: ModelContext) throws -> QSO? {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Fill nil/empty fields in winner from loser
    private func absorbFields(from loser: QSO, into winner: QSO) {
        // Fill nil fields from loser using nil-coalescing
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

        // Absorb band if winner has empty band
        let winnerBand = winner.band.trimmingCharacters(in: .whitespaces)
        let loserBand = loser.band.trimmingCharacters(in: .whitespaces)
        if winnerBand.isEmpty, !loserBand.isEmpty {
            winner.band = loser.band
        }
    }

    /// Transfer service presence records from loser to winner
    private func absorbServicePresence(from loser: QSO, into winner: QSO) {
        for presence in loser.servicePresence {
            // For POTA with park-specific presence, check if winner has this specific park
            if presence.serviceType == .pota, let parkRef = presence.parkReference {
                if let existing = winner.potaPresence(forPark: parkRef) {
                    // Update if loser's is "better"
                    if presence.isPresent, !existing.isPresent {
                        existing.isPresent = true
                        existing.needsUpload = false
                        existing.lastConfirmedAt = presence.lastConfirmedAt
                    }
                } else {
                    // Transfer the presence record to winner
                    presence.qso = winner
                    winner.servicePresence.append(presence)
                }
            } else if let existing = winner.presence(for: presence.serviceType) {
                // Non-POTA or legacy POTA presence
                if presence.isPresent, !existing.isPresent {
                    existing.isPresent = true
                    existing.needsUpload = false
                    existing.lastConfirmedAt = presence.lastConfirmedAt
                }
            } else {
                // Transfer the presence record to winner
                presence.qso = winner
                winner.servicePresence.append(presence)
            }
        }
    }
}
