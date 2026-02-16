import CarrierWaveCore
import Foundation
import SwiftData

/// One-time repair service to detect and merge duplicate QSOs caused by PHONE vs SSB
/// mode mismatch between POTA (uses PHONE) and QRZ (uses SSB).
///
/// Detection criteria:
/// - Same callsign (case-insensitive)
/// - Same band
/// - Timestamps within 120 seconds (2-minute dedup window)
/// - One mode is PHONE, the other is SSB
///
/// Merge strategy:
/// - Prefer QSO with more service presence data (richer sync state)
/// - Absorb fields and service presence from loser into winner
/// - Normalize winner's mode to SSB (canonical form)
/// - Delete the loser after merge
actor PhoneSSBDuplicateRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult: Sendable {
        let duplicatesFound: Int
        let qsosMerged: Int
    }

    let container: ModelContainer

    /// Count potential PHONE/SSB duplicate pairs
    func countDuplicates() throws -> Int {
        try findDuplicatePairs().count
    }

    /// Repair duplicates by merging PHONE/SSB pairs
    func repairDuplicates() throws -> RepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let pairs = try findDuplicatePairs()
        var totalMerged = 0

        for pair in pairs {
            guard let winner = try fetchQSO(id: pair.winnerId, context: context),
                  let loser = try fetchQSO(id: pair.loserId, context: context)
            else {
                continue
            }

            absorbFields(from: loser, into: winner)
            absorbServicePresence(from: loser, into: winner)

            // Normalize to canonical mode (SSB)
            winner.mode = ModeEquivalence.canonicalName(winner.mode)

            context.delete(loser)
            totalMerged += 1
        }

        if totalMerged > 0 {
            try context.save()
        }

        return RepairResult(duplicatesFound: pairs.count, qsosMerged: totalMerged)
    }

    // MARK: Private

    private struct DuplicatePair {
        let winnerId: UUID
        let loserId: UUID
    }

    private static let targetModes: Set<String> = ["PHONE", "SSB"]

    /// Find all PHONE/SSB duplicate pairs by scanning QSOs
    private func findDuplicatePairs() throws -> [DuplicatePair] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch all non-hidden QSOs, then filter to PHONE/SSB in memory
        // (SwiftData #Predicate can't handle many || conditions without type-check timeout)
        let descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { !$0.isHidden },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let allQSOs = try context.fetch(descriptor)
        let candidates = allQSOs.filter { Self.targetModes.contains($0.mode.uppercased()) }

        // Group by a loose key: callsign + band + timestamp bucket
        var groups: [String: [QSO]] = [:]
        for qso in candidates {
            let rounded = Int(qso.timestamp.timeIntervalSince1970 / 120) * 120
            let key = "\(qso.callsign.uppercased())|\(qso.band.uppercased())|\(rounded)"
            groups[key, default: []].append(qso)
        }

        // Find groups that have both PHONE and SSB
        var pairs: [DuplicatePair] = []
        for (_, group) in groups {
            pairs.append(contentsOf: matchPhoneSSBPairs(in: group))
        }
        return pairs
    }

    /// Match PHONE QSOs to SSB QSOs within a candidate group
    private func matchPhoneSSBPairs(in group: [QSO]) -> [DuplicatePair] {
        let phoneQSOs = group.filter { $0.mode.uppercased() == "PHONE" }
        let ssbQSOs = group.filter { $0.mode.uppercased() == "SSB" }

        guard !phoneQSOs.isEmpty, !ssbQSOs.isEmpty else {
            return []
        }

        var pairs: [DuplicatePair] = []
        for phoneQSO in phoneQSOs {
            if let bestSSB = ssbQSOs.min(by: {
                abs($0.timestamp.timeIntervalSince(phoneQSO.timestamp))
                    < abs($1.timestamp.timeIntervalSince(phoneQSO.timestamp))
            }) {
                let timeDiff = abs(
                    bestSSB.timestamp.timeIntervalSince(phoneQSO.timestamp)
                )
                guard timeDiff <= 120 else {
                    continue
                }

                // Winner is the one with more service presence
                let phoneScore = phoneQSO.servicePresence.filter(\.isPresent).count
                let ssbScore = bestSSB.servicePresence.filter(\.isPresent).count

                if ssbScore >= phoneScore {
                    pairs.append(DuplicatePair(winnerId: bestSSB.id, loserId: phoneQSO.id))
                } else {
                    pairs.append(DuplicatePair(winnerId: phoneQSO.id, loserId: bestSSB.id))
                }
            }
        }
        return pairs
    }

    private func fetchQSO(id: UUID, context: ModelContext) throws -> QSO? {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Fill nil/empty fields in winner from loser
    private func absorbFields(from loser: QSO, into winner: QSO) {
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

        // Merge park references
        winner.parkReference = FetchedQSO.combineParkReferences(
            winner.parkReference, loser.parkReference
        )
        winner.theirParkReference = FetchedQSO.combineParkReferences(
            winner.theirParkReference, loser.theirParkReference
        )

        // Absorb band if winner has empty band
        let winnerBand = winner.band.trimmingCharacters(in: .whitespaces)
        let loserBand = loser.band.trimmingCharacters(in: .whitespaces)
        if winnerBand.isEmpty, !loserBand.isEmpty {
            winner.band = loser.band
        }

        // Absorb confirmation flags
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
    private func absorbServicePresence(from loser: QSO, into winner: QSO) {
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
}
