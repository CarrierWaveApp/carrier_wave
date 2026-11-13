import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QSOProcessingActor Data Repairs

extension QSOProcessingActor {
    // MARK: - Callsign Whitespace Repair

    /// Result of callsign whitespace repair
    struct CallsignWhitespaceRepairResult {
        let trimmedCount: Int
        let mergedCount: Int
        let deletedCount: Int
    }

    /// Repair QSOs with leading/trailing whitespace in callsigns.
    /// Trims whitespace, then merges any resulting duplicates (e.g., "F5MQU " → "F5MQU"
    /// now matches existing "F5MQU" from POTA import). Merging absorbs fields and
    /// service presence from the loser into the winner.
    ///
    /// Processes in batches to cap memory usage — each batch uses a fresh ModelContext
    /// so model objects are released between iterations. Modified/deleted QSOs won't
    /// appear in subsequent fetches, so no offset tracking is needed.
    func repairCallsignWhitespace(
        container: ModelContainer
    ) async throws -> CallsignWhitespaceRepairResult {
        var trimmedCount = 0
        var mergedCount = 0
        var deletedCount = 0
        let batchSize = 200

        while true {
            try Task.checkCancellation()

            // Fresh context per batch to release model objects between iterations
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let spaceDescriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate<QSO> { $0.callsign.contains(" ") },
                limit: batchSize
            )
            let candidates = try context.boundedFetch(spaceDescriptor)
            let needsTrimming = candidates.filter {
                $0.callsign.trimmingCharacters(in: .whitespaces) != $0.callsign
            }

            if needsTrimming.isEmpty {
                break
            }

            for qso in needsTrimming {
                let result = try repairSingleCallsignWhitespace(
                    qso: qso, context: context
                )
                trimmedCount += result.trimmedCount
                mergedCount += result.mergedCount
                deletedCount += result.deletedCount
            }

            try context.save()
        }

        return CallsignWhitespaceRepairResult(
            trimmedCount: trimmedCount,
            mergedCount: mergedCount,
            deletedCount: deletedCount
        )
    }

    /// Repair a single QSO's callsign whitespace, merging with existing if needed.
    private func repairSingleCallsignWhitespace(
        qso: QSO, context: ModelContext
    ) throws -> CallsignWhitespaceRepairResult {
        let trimmedCallsign = qso.callsign
            .trimmingCharacters(in: .whitespaces).uppercased()
        let key = trimmedDedupeKey(for: qso)

        let matchDescriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { $0.callsign == trimmedCallsign },
            limit: 100
        )
        let matches = try context.boundedFetch(matchDescriptor)
        let qsoId = qso.id
        let winner = matches.first {
            $0.id != qsoId && trimmedDedupeKey(for: $0) == key
        }

        if let winner {
            absorbFields(from: qso, into: winner)
            absorbServicePresence(from: qso, into: winner, context: context)
            context.delete(qso)
            return CallsignWhitespaceRepairResult(trimmedCount: 0, mergedCount: 1, deletedCount: 1)
        } else {
            qso.callsign = trimmedCallsign
            return CallsignWhitespaceRepairResult(trimmedCount: 1, mergedCount: 0, deletedCount: 0)
        }
    }

    /// Compute a dedup key using trimmed callsign (for whitespace repair matching)
    private func trimmedDedupeKey(for qso: QSO) -> String {
        let trimmedCallsign = qso.callsign
            .trimmingCharacters(in: .whitespaces).uppercased()
        let canonicalMode = ModeEquivalence.canonicalNameForDedup(qso.mode)
        let rounded = Int(qso.timestamp.timeIntervalSince1970 / 120) * 120
        return "\(trimmedCallsign)|\(qso.band.uppercased())|\(canonicalMode)|\(rounded)"
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
    struct QRZSubmittedRepairResult {
        let repairedCount: Int
    }

    /// Repair QRZ ServicePresence records stuck in isSubmitted=true state.
    /// QRZ uploads are synchronous — if the HTTP request succeeded, the QSO is present.
    /// A bug in uploadToQRZ set isSubmitted=true instead of isPresent=true, leaving
    /// QSOs in a limbo state invisible to reconciliation.
    /// Uses batched fetching with fresh contexts to cap memory usage.
    func repairQRZSubmittedState(
        container: ModelContainer
    ) async throws -> QRZSubmittedRepairResult {
        var repairedCount = 0
        let batchSize = 500
        var offset = 0

        while true {
            try Task.checkCancellation()
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate<ServicePresence> { $0.isSubmitted },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            var batchRepaired = 0
            for presence in batch {
                guard presence.serviceType == .qrz else {
                    continue
                }
                guard let qso = presence.qso, !qso.isHidden else {
                    continue
                }
                presence.isPresent = true
                presence.isSubmitted = false
                presence.lastConfirmedAt = Date()
                batchRepaired += 1
            }

            if batchRepaired > 0 {
                try context.save()
            }
            repairedCount += batchRepaired
            // Modified records drop out of isSubmitted predicate
            offset += batch.count - batchRepaired
            await Task.yield()
        }

        return QRZSubmittedRepairResult(repairedCount: repairedCount)
    }

    // MARK: - QRZ LogId Duplicate Repair

    /// Result of QRZ logId dedup repair
    struct QRZLogIdDedupResult {
        let mergedCount: Int
        let deletedCount: Int
    }

    /// Find and merge QSOs that share the same qrzLogId.
    /// A dedup key mismatch between FetchedQSO and computeDeduplicationKey
    /// could create duplicate local QSOs with the same qrzLogId. Both copies
    /// get isPresent=true and qrzConfirmed=true, inflating sync counts.
    /// This repair keeps the older QSO (winner) and merges the newer one.
    func repairDuplicateQRZLogIds(
        container: ModelContainer
    ) async throws -> QRZLogIdDedupResult {
        let logIdToQSOIds = try await collectQRZLogIdMap(
            container: container
        )

        let duplicateLogIds = logIdToQSOIds.filter { $0.value.count > 1 }
        guard !duplicateLogIds.isEmpty else {
            return QRZLogIdDedupResult(
                mergedCount: 0, deletedCount: 0
            )
        }

        return try await mergeDuplicateQRZLogIds(
            duplicateLogIds, container: container
        )
    }

    /// Collect a map of qrzLogId → [QSO UUID] in batches.
    private func collectQRZLogIdMap(
        container: ModelContainer
    ) async throws -> [String: [UUID]] {
        var logIdToQSOIds: [String: [UUID]] = [:]
        let batchSize = 500
        var offset = 0

        while true {
            try Task.checkCancellation()
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate<QSO> {
                    $0.qrzLogId != nil && !$0.isHidden
                },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            for qso in batch {
                if let logId = qso.qrzLogId {
                    logIdToQSOIds[logId, default: []].append(qso.id)
                }
            }

            offset += batch.count
            if batch.count < batchSize {
                break
            }
            await Task.yield()
        }

        return logIdToQSOIds
    }

    /// Merge duplicate QSOs that share the same qrzLogId.
    /// Keeps the oldest QSO as winner, absorbs newer duplicates.
    private func mergeDuplicateQRZLogIds(
        _ duplicateLogIds: [String: [UUID]],
        container: ModelContainer
    ) async throws -> QRZLogIdDedupResult {
        var mergedCount = 0
        var deletedCount = 0

        for (_, qsoIds) in duplicateLogIds {
            try Task.checkCancellation()
            let context = ModelContext(container)
            context.autosaveEnabled = false

            // Fetch all candidates in one query to avoid repeated
            // #Predicate creation in a loop — SwiftData's key path
            // cache can hit an assertion failure when predicates with
            // captured variables are created rapidly on background threads.
            let idSet = Set(qsoIds)
            let desc = BoundedDescriptor<QSO>(
                predicate: #Predicate<QSO> { idSet.contains($0.id) },
                limit: min(qsoIds.count, BoundedDescriptor<QSO>.maxLimit)
            )
            let qsos = try context.boundedFetch(desc)

            guard qsos.count > 1 else {
                continue
            }

            // Sort by timestamp (oldest first) — keep the original
            let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
            let winner = sorted[0]
            for loser in sorted.dropFirst() {
                absorbFields(from: loser, into: winner)
                absorbServicePresence(
                    from: loser, into: winner, context: context
                )
                context.delete(loser)
                mergedCount += 1
                deletedCount += 1
            }

            try context.save()
            await Task.yield()
        }

        return QRZLogIdDedupResult(
            mergedCount: mergedCount, deletedCount: deletedCount
        )
    }
}
