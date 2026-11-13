import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - ImportService QRZ Import

extension ImportService {
    func importFromQRZ(qsos: [QRZFetchedQSO], myCallsign: String) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        var imported = 0
        var updated = 0
        var ledgerQSOs: [QSO] = []
        var touched: [QSO] = []

        // Build lookup dictionaries in batches to avoid loading all QSOs at once
        let (byQrzLogId, byDedupeKey) = try fetchQRZLookupDictionaries()

        for qrzQso in qsos {
            let result = processQRZQso(
                qrzQso, myCallsign: myCallsign, byQrzLogId: byQrzLogId, byDedupeKey: byDedupeKey
            )
            switch result {
            case let .updated(qsos): updated += 1; touched.append(contentsOf: qsos)
            case let .imported(qso): ledgerQSOs.append(qso); touched.append(qso); imported += 1
            }
        }

        try await commitImportedQSOs(touched)
        QSOLedger.appendBatch(ledgerQSOs)
        let result = ImportResult(
            totalRecords: qsos.count, imported: imported, duplicates: 0, errors: 0, matched: updated
        )
        lastImportResult = result
        return result
    }

    func processQRZQso(
        _ qrzQso: QRZFetchedQSO,
        myCallsign: String,
        byQrzLogId: [String: UUID],
        byDedupeKey: [String: UUID]
    ) -> QSOProcessResult {
        // Try to find existing by QRZ log ID first
        if let qrzLogId = qrzQso.qrzLogId,
           let existingId = byQrzLogId[qrzLogId],
           let existing = fetchQSO(byId: existingId)
        {
            existing.qrzConfirmed = qrzQso.qrzConfirmed
            existing.lotwConfirmedDate = qrzQso.lotwConfirmedDate
            existing.dxcc = existing.dxcc ?? qrzQso.dxcc
            existing.markPresent(in: .qrz, context: modelContext)
            return .updated([existing])
        }

        // Try to find by deduplication key
        let tempQso = QSO(
            callsign: qrzQso.callsign, band: qrzQso.band, mode: qrzQso.mode,
            timestamp: qrzQso.timestamp, myCallsign: qrzQso.myCallsign ?? myCallsign,
            importSource: .qrz
        )

        if let existingId = byDedupeKey[tempQso.deduplicationKey],
           let existing = fetchQSO(byId: existingId)
        {
            existing.qrzLogId = qrzQso.qrzLogId
            existing.qrzConfirmed = qrzQso.qrzConfirmed
            existing.lotwConfirmedDate = qrzQso.lotwConfirmedDate
            existing.dxcc = existing.dxcc ?? qrzQso.dxcc
            existing.markPresent(in: .qrz, context: modelContext)
            return .updated([existing])
        }

        // Create new QSO
        let newQso = createQSOFromQRZ(qrzQso, myCallsign: myCallsign)
        modelContext.insert(newQso)
        createServicePresenceRecords(for: newQso, importedFrom: .qrz)
        return .imported(newQso)
    }

    func createQSOFromQRZ(_ qrzQso: QRZFetchedQSO, myCallsign: String) -> QSO {
        // MY_SIG_INFO → my activation park
        var parkReference = qrzQso.parkReference.flatMap { ParkReference.sanitizeMulti($0) }
        var theirParkReference = qrzQso.theirParkReference.flatMap { ParkReference.sanitize($0) }

        // Apply user's comment park action for park refs found in notes
        let notesRef = qrzQso.notes.flatMap { ParkReference.extractFromFreeText($0) }
        if let notesRef {
            switch CommentParkAction.current {
            case .ignore:
                break
            case .theirPark:
                theirParkReference = theirParkReference ?? notesRef
            case .myPark:
                parkReference = parkReference ?? notesRef
            }
        }

        return QSO(
            callsign: qrzQso.callsign, band: qrzQso.band, mode: qrzQso.mode,
            frequency: qrzQso.frequency, timestamp: qrzQso.timestamp,
            rstSent: qrzQso.rstSent, rstReceived: qrzQso.rstReceived,
            myCallsign: qrzQso.myCallsign ?? myCallsign, myGrid: qrzQso.myGrid,
            theirGrid: qrzQso.theirGrid,
            parkReference: parkReference,
            theirParkReference: theirParkReference,
            notes: qrzQso.notes, importSource: .qrz,
            rawADIF: qrzQso.rawADIF, qrzLogId: qrzQso.qrzLogId,
            qrzConfirmed: qrzQso.qrzConfirmed, lotwConfirmedDate: qrzQso.lotwConfirmedDate,
            dxcc: qrzQso.dxcc
        )
    }
}

// MARK: - ImportService POTA Import

extension ImportService {
    func importFromPOTA(qsos: [POTAFetchedQSO]) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        var imported = 0
        var updated = 0
        var ledgerQSOs: [QSO] = []
        var touched: [QSO] = []

        // Build lookup dictionary in batches to avoid loading all QSOs at once
        let byDedupeKey = try fetchDedupeKeyLookup()

        for potaQso in qsos {
            let result = processPOTAQso(potaQso, byDedupeKey: byDedupeKey)
            switch result {
            case let .updated(qsos): updated += 1; touched.append(contentsOf: qsos)
            case let .imported(qso): ledgerQSOs.append(qso); touched.append(qso); imported += 1
            }
        }

        try await commitImportedQSOs(touched)
        QSOLedger.appendBatch(ledgerQSOs)

        let result = ImportResult(
            totalRecords: qsos.count,
            imported: imported,
            duplicates: 0,
            errors: 0,
            matched: updated
        )

        lastImportResult = result
        return result
    }

    func processPOTAQso(_ potaQso: POTAFetchedQSO, byDedupeKey: [String: UUID]) -> QSOProcessResult {
        let rounded = Int(potaQso.timestamp.timeIntervalSince1970 / 120) * 120
        let call = potaQso.callsign.uppercased()
        let normalizedMode = ModeEquivalence.canonicalNameForDedup(potaQso.mode)
        let dedupeKey =
            "\(call)|\(potaQso.band.uppercased())|\(normalizedMode)|\(rounded)"

        if let existingId = byDedupeKey[dedupeKey],
           let existing = fetchQSO(byId: existingId)
        {
            existing.parkReference =
                existing.parkReference.nonEmpty
                    ?? potaQso.parkReference.flatMap { ParkReference.sanitizeMulti($0) }
            existing.rstSent = existing.rstSent.nonEmpty ?? potaQso.rstSent
            existing.rstReceived = existing.rstReceived.nonEmpty ?? potaQso.rstReceived
            existing.markPresent(in: .pota, context: modelContext)
            return .updated([existing])
        }

        let newQso = createQSOFromPOTA(potaQso)
        modelContext.insert(newQso)
        createServicePresenceRecords(for: newQso, importedFrom: .pota)
        return .imported(newQso)
    }

    func createQSOFromPOTA(_ pq: POTAFetchedQSO) -> QSO {
        QSO(
            callsign: pq.callsign, band: pq.band, mode: pq.mode, frequency: nil,
            timestamp: pq.timestamp, rstSent: pq.rstSent, rstReceived: pq.rstReceived,
            myCallsign: pq.myCallsign, myGrid: nil, theirGrid: nil,
            parkReference: pq.parkReference.flatMap { ParkReference.sanitizeMulti($0) },
            notes: nil, importSource: .pota, rawADIF: nil
        )
    }
}

// MARK: - Batched Lookup Helpers

extension ImportService {
    /// Build QRZ lookup dictionaries in batches to avoid loading all QSOs at once.
    /// Returns lightweight (key → UUID) maps (~20 MB) instead of full QSO objects (~400 MB).
    func fetchQRZLookupDictionaries() throws -> (
        byQrzLogId: [String: UUID],
        byDedupeKey: [String: UUID]
    ) {
        let batchSize = 1_000
        var offset = 0
        var byQrzLogId: [String: UUID] = [:]
        var byDedupeKey: [String: UUID] = [:]

        while true {
            let batchContext = ModelContext(modelContext.container)
            batchContext.autosaveEnabled = false
            let descriptor = BoundedDescriptor<QSO>(
                limit: batchSize,
                offset: offset
            )

            let batch = try batchContext.boundedFetch(descriptor)
            guard !batch.isEmpty else {
                break
            }

            for qso in batch {
                if let logId = qso.qrzLogId {
                    byQrzLogId[logId] = qso.id
                }
                byDedupeKey[qso.deduplicationKey] = qso.id
            }

            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }

        return (byQrzLogId, byDedupeKey)
    }

    /// Build dedup key → UUID lookup dictionary in batches.
    func fetchDedupeKeyLookup() throws -> [String: UUID] {
        let batchSize = 1_000
        var offset = 0
        var byDedupeKey: [String: UUID] = [:]

        while true {
            let batchContext = ModelContext(modelContext.container)
            batchContext.autosaveEnabled = false
            let descriptor = BoundedDescriptor<QSO>(
                limit: batchSize,
                offset: offset
            )

            let batch = try batchContext.boundedFetch(descriptor)
            guard !batch.isEmpty else {
                break
            }

            for qso in batch {
                byDedupeKey[qso.deduplicationKey] = qso.id
            }

            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }

        return byDedupeKey
    }

    /// Fetch a single QSO by ID from the main context for mutation.
    func fetchQSO(byId qsoId: UUID) -> QSO? {
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.id == qsoId },
            limit: 1
        )
        return try? modelContext.boundedFetch(descriptor).first
    }
}
