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

    struct DuplicateGroup: Sendable {
        let winnerId: UUID
        let loserIds: [UUID]
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

    /// Sendable snapshot of QSO data needed for duplicate detection
    private struct QSOSnapshot: Sendable {
        let id: UUID
        let callsign: String
        let timestamp: Date
        let band: String
        let mode: String
        let parkReference: String?
    }

    /// Phone mode family - all considered equivalent for deduplication
    private static let phoneModes: Set<String> = ["PHONE", "SSB", "USB", "LSB", "AM", "FM", "DV"]

    /// Digital mode family - all considered equivalent for deduplication
    private static let digitalModes: Set<String> = [
        "DATA", "FT8", "FT4", "PSK31", "PSK", "RTTY", "JT65", "JT9", "MFSK", "OLIVIA",
    ]

    /// Time window for considering QSOs as duplicates (60 seconds)
    private static let timeWindowSeconds: TimeInterval = 60

    /// Find all duplicate groups by scanning QSOs with multi-park references
    private func findDuplicateGroups() throws -> [DuplicateGroup] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch all QSOs with park references containing commas (two-fers)
        let descriptor = FetchDescriptor<QSO>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let allQSOs = try context.fetch(descriptor)

        // Convert to sendable snapshots immediately
        let allSnapshots = allQSOs.map { qso in
            QSOSnapshot(
                id: qso.id,
                callsign: qso.callsign,
                timestamp: qso.timestamp,
                band: qso.band,
                mode: qso.mode,
                parkReference: qso.parkReference
            )
        }

        // Find QSOs with multi-park references
        let multiParkSnapshots = allSnapshots.filter { snapshot in
            guard let parkRef = snapshot.parkReference, !parkRef.isEmpty else {
                return false
            }
            return POTAClient.isMultiPark(parkRef)
        }

        var groups: [DuplicateGroup] = []
        var processedIds = Set<UUID>()

        for multiParkSnapshot in multiParkSnapshots {
            if processedIds.contains(multiParkSnapshot.id) {
                continue
            }

            // Find potential duplicates for this multi-park QSO
            let duplicateIds = findDuplicatesFor(multiParkSnapshot, in: allSnapshots)

            if !duplicateIds.isEmpty {
                // Winner is the multi-park QSO (most complete)
                groups.append(
                    DuplicateGroup(
                        winnerId: multiParkSnapshot.id,
                        loserIds: duplicateIds
                    )
                )

                processedIds.insert(multiParkSnapshot.id)
                for id in duplicateIds {
                    processedIds.insert(id)
                }
            }
        }

        return groups
    }

    /// Find duplicates for a multi-park QSO snapshot
    private func findDuplicatesFor(_ multiParkSnapshot: QSOSnapshot, in allSnapshots: [QSOSnapshot])
        -> [UUID]
    {
        guard let multiParkRef = multiParkSnapshot.parkReference else {
            return []
        }

        let multiParks = POTAClient.splitParkReferences(multiParkRef)

        return allSnapshots.compactMap { candidate -> UUID? in
            // Not the same QSO
            guard candidate.id != multiParkSnapshot.id else {
                return nil
            }

            // Must have a park reference
            guard let candidateParkRef = candidate.parkReference, !candidateParkRef.isEmpty else {
                return nil
            }

            // Candidate should NOT be a multi-park (we want to merge singles into multi)
            // OR it should be a truncated version (shorter)
            let candidateParks = POTAClient.splitParkReferences(candidateParkRef)
            guard
                candidateParks.count < multiParks.count
                || candidateParkRef.count < multiParkRef.count
            else {
                return nil
            }

            // Check if candidate's park(s) are a subset of multi-park's parks
            // or if candidate looks like a truncated version
            let isSubset = candidateParks.allSatisfy { park in
                multiParks.contains { multiPark in
                    multiPark == park || multiPark.hasPrefix(park)
                }
            }

            guard isSubset else {
                return nil
            }

            // Same callsign
            guard multiParkSnapshot.callsign.uppercased() == candidate.callsign.uppercased() else {
                return nil
            }

            // Timestamps within window
            let timeDiff = abs(
                multiParkSnapshot.timestamp.timeIntervalSince(candidate.timestamp)
            )
            guard timeDiff <= Self.timeWindowSeconds else {
                return nil
            }

            // Same band (or one is empty)
            let band1 = multiParkSnapshot.band.trimmingCharacters(in: .whitespaces).uppercased()
            let band2 = candidate.band.trimmingCharacters(in: .whitespaces).uppercased()
            if !band1.isEmpty, !band2.isEmpty, band1 != band2 {
                return nil
            }

            // Same mode family
            guard modesAreEquivalent(multiParkSnapshot.mode, candidate.mode) else {
                return nil
            }

            return candidate.id
        }
    }

    /// Check if two modes are equivalent
    private func modesAreEquivalent(_ mode1: String, _ mode2: String) -> Bool {
        let m1 = mode1.uppercased()
        let m2 = mode2.uppercased()

        if m1 == m2 {
            return true
        }

        if Self.phoneModes.contains(m1), Self.phoneModes.contains(m2) {
            return true
        }
        if Self.digitalModes.contains(m1), Self.digitalModes.contains(m2) {
            return true
        }

        return false
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
        if winner.rstSent == nil {
            winner.rstSent = loser.rstSent
        }
        if winner.rstReceived == nil {
            winner.rstReceived = loser.rstReceived
        }
        if winner.myGrid == nil {
            winner.myGrid = loser.myGrid
        }
        if winner.theirGrid == nil {
            winner.theirGrid = loser.theirGrid
        }
        if winner.notes == nil {
            winner.notes = loser.notes
        }
        if winner.qrzLogId == nil {
            winner.qrzLogId = loser.qrzLogId
        }
        if winner.rawADIF == nil {
            winner.rawADIF = loser.rawADIF
        }
        if winner.frequency == nil {
            winner.frequency = loser.frequency
        }
        if winner.name == nil {
            winner.name = loser.name
        }
        if winner.qth == nil {
            winner.qth = loser.qth
        }
        if winner.state == nil {
            winner.state = loser.state
        }
        if winner.country == nil {
            winner.country = loser.country
        }
        if winner.power == nil {
            winner.power = loser.power
        }
        if winner.theirLicenseClass == nil {
            winner.theirLicenseClass = loser.theirLicenseClass
        }

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
