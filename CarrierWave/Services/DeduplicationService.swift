import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - DeduplicationResult

struct DeduplicationResult {
    let duplicateGroupsFound: Int
    let qsosMerged: Int
    let qsosRemoved: Int
}

// MARK: - DeduplicationService

@MainActor
final class DeduplicationService {
    // MARK: Lifecycle

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: Internal

    /// Find and merge duplicate QSOs within the given time window
    func findAndMergeDuplicates(timeWindowMinutes: Int = 5) throws -> DeduplicationResult {
        // Fetch all QSOs sorted by timestamp
        let descriptor = FetchDescriptor<QSO>(sortBy: [SortDescriptor(\.timestamp)])
        let allQSOs = try modelContext.fetch(descriptor)

        if allQSOs.isEmpty {
            return DeduplicationResult(duplicateGroupsFound: 0, qsosMerged: 0, qsosRemoved: 0)
        }

        // Convert to snapshots for pure logic matching
        let snapshots = allQSOs.map { $0.toSnapshot() }

        // Use CarrierWaveCore's deduplication matcher
        let config = DeduplicationConfig(
            timeWindowSeconds: TimeInterval(timeWindowMinutes * 60),
            requireBandMatch: true,
            requireParkMatch: true
        )
        let groups = DeduplicationMatcher.findDuplicateGroups(snapshots, config: config)

        // Merge each group
        var totalMerged = 0
        var totalRemoved = 0

        // Build lookup for QSOs by ID
        let qsoById = Dictionary(uniqueKeysWithValues: allQSOs.map { ($0.id, $0) })

        for group in groups {
            guard let winner = qsoById[group.winnerId] else {
                continue
            }

            for loserId in group.loserIds {
                guard let loser = qsoById[loserId] else {
                    continue
                }

                absorbFields(from: loser, into: winner)
                absorbServicePresence(from: loser, into: winner)
                modelContext.delete(loser)
                totalRemoved += 1
            }
            totalMerged += 1
        }

        try modelContext.save()

        return DeduplicationResult(
            duplicateGroupsFound: groups.count,
            qsosMerged: totalMerged,
            qsosRemoved: totalRemoved
        )
    }

    // MARK: Private

    private let modelContext: ModelContext

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
        if winner.parkReference == nil {
            winner.parkReference = loser.parkReference
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
            // Check if winner already has this service
            if let existing = winner.presence(for: presence.serviceType) {
                // Update if loser's is "better" (present beats not present)
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

// MARK: - QSO Extension for Snapshot Conversion

extension QSO {
    /// Convert QSO to a CarrierWaveCore QSOSnapshot for deduplication
    func toSnapshot() -> QSOSnapshot {
        QSOSnapshot(
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
            syncedServicesCount: syncedServicesCount
        )
    }
}
