import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - ImportService QRZ Import

extension ImportService {
    func importFromQRZ(qsos: [QRZFetchedQSO], myCallsign: String) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        var imported = 0
        var updated = 0

        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)
        let byQrzLogId = Dictionary(grouping: existingQSOs.filter { $0.qrzLogId != nil }) {
            $0.qrzLogId!
        }
        let byDedupeKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }

        for qrzQso in qsos {
            let result = processQRZQso(
                qrzQso, myCallsign: myCallsign, byQrzLogId: byQrzLogId, byDedupeKey: byDedupeKey
            )
            switch result {
            case .updated: updated += 1
            case .imported: imported += 1
            }
        }

        try modelContext.save()
        let result = ImportResult(
            totalRecords: qsos.count, imported: imported, duplicates: 0, errors: 0, matched: updated
        )
        lastImportResult = result
        return result
    }

    func processQRZQso(
        _ qrzQso: QRZFetchedQSO,
        myCallsign: String,
        byQrzLogId: [String: [QSO]],
        byDedupeKey: [String: [QSO]]
    ) -> QSOProcessResult {
        // Try to find existing by QRZ log ID first
        if let qrzLogId = qrzQso.qrzLogId, let existing = byQrzLogId[qrzLogId]?.first {
            existing.qrzConfirmed = qrzQso.qrzConfirmed
            existing.lotwConfirmedDate = qrzQso.lotwConfirmedDate
            existing.dxcc = existing.dxcc ?? qrzQso.dxcc
            existing.markPresent(in: .qrz, context: modelContext)
            return .updated
        }

        // Try to find by deduplication key
        let tempQso = QSO(
            callsign: qrzQso.callsign, band: qrzQso.band, mode: qrzQso.mode,
            timestamp: qrzQso.timestamp, myCallsign: qrzQso.myCallsign ?? myCallsign,
            importSource: .qrz
        )

        if let existing = byDedupeKey[tempQso.deduplicationKey]?.first {
            existing.qrzLogId = qrzQso.qrzLogId
            existing.qrzConfirmed = qrzQso.qrzConfirmed
            existing.lotwConfirmedDate = qrzQso.lotwConfirmedDate
            existing.dxcc = existing.dxcc ?? qrzQso.dxcc
            existing.markPresent(in: .qrz, context: modelContext)
            return .updated
        }

        // Create new QSO
        let newQso = createQSOFromQRZ(qrzQso, myCallsign: myCallsign)
        modelContext.insert(newQso)
        createServicePresenceRecords(for: newQso, importedFrom: .qrz)
        return .imported
    }

    func createQSOFromQRZ(_ qrzQso: QRZFetchedQSO, myCallsign: String) -> QSO {
        QSO(
            callsign: qrzQso.callsign, band: qrzQso.band, mode: qrzQso.mode,
            frequency: qrzQso.frequency, timestamp: qrzQso.timestamp,
            rstSent: qrzQso.rstSent, rstReceived: qrzQso.rstReceived,
            myCallsign: qrzQso.myCallsign ?? myCallsign, myGrid: qrzQso.myGrid,
            theirGrid: qrzQso.theirGrid,
            parkReference: qrzQso.parkReference.flatMap { ParkReference.sanitizeMulti($0) },
            theirParkReference: qrzQso.theirParkReference.flatMap { ParkReference.sanitize($0) },
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

        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)
        let byDedupeKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }

        for potaQso in qsos {
            let result = processPOTAQso(potaQso, byDedupeKey: byDedupeKey)
            switch result {
            case .updated: updated += 1
            case .imported: imported += 1
            }
        }

        try modelContext.save()

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

    func processPOTAQso(_ potaQso: POTAFetchedQSO, byDedupeKey: [String: [QSO]]) -> QSOProcessResult {
        let rounded = Int(potaQso.timestamp.timeIntervalSince1970 / 120) * 120
        let call = potaQso.callsign.uppercased()
        let dedupeKey =
            "\(call)|\(potaQso.band.uppercased())|\(potaQso.mode.uppercased())|\(rounded)"

        if let existing = byDedupeKey[dedupeKey]?.first {
            existing.parkReference =
                existing.parkReference.nonEmpty
                    ?? potaQso.parkReference.flatMap { ParkReference.sanitizeMulti($0) }
            existing.rstSent = existing.rstSent.nonEmpty ?? potaQso.rstSent
            existing.rstReceived = existing.rstReceived.nonEmpty ?? potaQso.rstReceived
            existing.markPresent(in: .pota, context: modelContext)
            return .updated
        }

        let newQso = createQSOFromPOTA(potaQso)
        modelContext.insert(newQso)
        createServicePresenceRecords(for: newQso, importedFrom: .pota)
        return .imported
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
