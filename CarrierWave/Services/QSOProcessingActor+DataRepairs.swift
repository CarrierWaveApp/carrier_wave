import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QSOProcessingActor Data Repairs

extension QSOProcessingActor {
    // MARK: - Callsign Whitespace Repair

    /// Result of callsign whitespace repair
    struct CallsignWhitespaceRepairResult: Sendable {
        let trimmedCount: Int
        let mergedCount: Int
        let deletedCount: Int
    }

    /// Repair QSOs with leading/trailing whitespace in callsigns.
    /// Trims whitespace, then merges any resulting duplicates (e.g., "F5MQU " → "F5MQU"
    /// now matches existing "F5MQU" from POTA import). Merging absorbs fields and
    /// service presence from the loser into the winner.
    ///
    /// Processes in batches to cap memory usage — each batch fetches, processes,
    /// and saves before moving to the next. Modified/deleted QSOs won't appear
    /// in subsequent fetches, so no offset tracking is needed.
    func repairCallsignWhitespace(
        container: ModelContainer
    ) async throws -> CallsignWhitespaceRepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var trimmedCount = 0
        var mergedCount = 0
        var deletedCount = 0
        let batchSize = 200

        while true {
            try Task.checkCancellation()

            // Fetch next batch of QSOs with spaces in callsigns.
            // Already-repaired QSOs drop out of the predicate, so we always
            // fetch from the start without an offset.
            var spaceDescriptor = FetchDescriptor<QSO>(
                predicate: #Predicate<QSO> { $0.callsign.contains(" ") }
            )
            spaceDescriptor.fetchLimit = batchSize
            let candidates = try context.fetch(spaceDescriptor)

            // Filter to those actually needing leading/trailing trim
            let needsTrimming = candidates.filter {
                $0.callsign.trimmingCharacters(in: .whitespaces) != $0.callsign
            }

            if needsTrimming.isEmpty {
                break
            }

            for qso in needsTrimming {
                let trimmedCallsign = qso.callsign
                    .trimmingCharacters(in: .whitespaces).uppercased()
                let key = trimmedDedupeKey(for: qso)

                // Find merge target: fetch QSOs with the clean callsign
                var matchDescriptor = FetchDescriptor<QSO>(
                    predicate: #Predicate<QSO> { $0.callsign == trimmedCallsign }
                )
                matchDescriptor.fetchLimit = 100
                let matches = try context.fetch(matchDescriptor)
                let qsoId = qso.id
                let winner = matches.first {
                    $0.id != qsoId && trimmedDedupeKey(for: $0) == key
                }

                if let winner {
                    absorbFields(from: qso, into: winner)
                    absorbServicePresence(from: qso, into: winner, context: context)
                    context.delete(qso)
                    mergedCount += 1
                    deletedCount += 1
                } else {
                    qso.callsign = trimmedCallsign
                    trimmedCount += 1
                }
            }

            // Save after each batch to release memory
            try context.save()
        }

        return CallsignWhitespaceRepairResult(
            trimmedCount: trimmedCount,
            mergedCount: mergedCount,
            deletedCount: deletedCount
        )
    }

    /// Compute a dedup key using trimmed callsign (for whitespace repair matching)
    private func trimmedDedupeKey(for qso: QSO) -> String {
        let trimmedCallsign = qso.callsign
            .trimmingCharacters(in: .whitespaces).uppercased()
        let rounded = Int(qso.timestamp.timeIntervalSince1970 / 120) * 120
        return "\(trimmedCallsign)|\(qso.band.uppercased())|\(qso.mode.uppercased())|\(rounded)"
    }

    /// Fill nil/empty fields in winner from loser
    private func absorbFields(from loser: QSO, into winner: QSO) {
        winner.rstSent = winner.rstSent.nonEmpty ?? loser.rstSent
        winner.rstReceived = winner.rstReceived.nonEmpty ?? loser.rstReceived
        winner.myGrid = winner.myGrid.nonEmpty ?? loser.myGrid
        winner.theirGrid = winner.theirGrid.nonEmpty ?? loser.theirGrid
        winner.parkReference = winner.parkReference.nonEmpty ?? loser.parkReference
        winner.theirParkReference = winner.theirParkReference.nonEmpty
            ?? loser.theirParkReference
        winner.notes = winner.notes.nonEmpty ?? loser.notes
        winner.qrzLogId = winner.qrzLogId ?? loser.qrzLogId
        winner.rawADIF = winner.rawADIF.nonEmpty ?? loser.rawADIF
        winner.frequency = winner.frequency ?? loser.frequency
        winner.name = winner.name.nonEmpty ?? loser.name
        winner.qth = winner.qth.nonEmpty ?? loser.qth
        winner.state = winner.state.nonEmpty ?? loser.state
        winner.country = winner.country.nonEmpty ?? loser.country
        winner.power = winner.power ?? loser.power
        winner.myRig = winner.myRig.nonEmpty ?? loser.myRig
        winner.sotaRef = winner.sotaRef.nonEmpty ?? loser.sotaRef
        winner.dxcc = winner.dxcc ?? loser.dxcc
        winner.qrzConfirmed = winner.qrzConfirmed || loser.qrzConfirmed
        winner.lotwConfirmed = winner.lotwConfirmed || loser.lotwConfirmed
        winner.lotwConfirmedDate = winner.lotwConfirmedDate ?? loser.lotwConfirmedDate

        // Absorb band if winner has empty band
        let winnerBand = winner.band.trimmingCharacters(in: .whitespaces)
        let loserBand = loser.band.trimmingCharacters(in: .whitespaces)
        if winnerBand.isEmpty, !loserBand.isEmpty {
            winner.band = loser.band
        }

        // Prefer specific mode over generic
        winner.mode = ModeEquivalence.moreSpecific(winner.mode, loser.mode)
    }

    /// Transfer service presence records from loser to winner
    private func absorbServicePresence(
        from loser: QSO, into winner: QSO, context: ModelContext
    ) {
        for presence in loser.servicePresence {
            if let existing = winner.presence(for: presence.serviceType) {
                // Promote isPresent if loser has it
                if presence.isPresent, !existing.isPresent {
                    existing.isPresent = true
                    existing.needsUpload = false
                    existing.isSubmitted = false
                    existing.lastConfirmedAt = presence.lastConfirmedAt
                }
            } else {
                // Transfer the presence record to winner
                presence.qso = winner
                winner.servicePresence.append(presence)
            }
        }
    }

    // MARK: - QRZ isSubmitted State Repair

    /// Result of QRZ submitted state repair
    struct QRZSubmittedRepairResult: Sendable {
        let repairedCount: Int
    }

    /// Repair QRZ ServicePresence records stuck in isSubmitted=true state.
    /// QRZ uploads are synchronous — if the HTTP request succeeded, the QSO is present.
    /// A bug in uploadToQRZ set isSubmitted=true instead of isPresent=true, leaving
    /// QSOs in a limbo state invisible to reconciliation.
    func repairQRZSubmittedState(
        container: ModelContainer
    ) async throws -> QRZSubmittedRepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch all isSubmitted ServicePresence records
        let descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { $0.isSubmitted }
        )
        let records = try context.fetch(descriptor)

        var repairedCount = 0
        var unsavedCount = 0

        for presence in records {
            try Task.checkCancellation()

            // Only repair QRZ records — POTA legitimately uses isSubmitted
            guard presence.serviceType == .qrz else {
                continue
            }
            guard let qso = presence.qso, !qso.isHidden else {
                continue
            }

            // QRZ uploads are synchronous: if submitted, it's present
            presence.isPresent = true
            presence.isSubmitted = false
            presence.lastConfirmedAt = Date()
            repairedCount += 1
            unsavedCount += 1

            if unsavedCount >= 100 {
                try context.save()
                unsavedCount = 0
            }
        }

        if unsavedCount > 0 {
            try context.save()
        }

        return QRZSubmittedRepairResult(repairedCount: repairedCount)
    }
}
