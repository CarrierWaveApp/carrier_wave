// Session-targeted ADIF import: scan for metadata, detect mismatches,
// and import QSOs into an existing LoggingSession.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

extension Notification.Name {
    static let sessionQSOsDidChange = Notification.Name("sessionQSOsDidChange")
}

// MARK: - Session Import Types

extension ImportService {
    /// Metadata detected from an ADIF file, for comparison with session values
    struct DetectedMetadata {
        let callsigns: Set<String>
        let parkReferences: Set<String>
        let recordCount: Int
    }

    /// Mismatches between ADIF metadata and the target session
    struct MetadataMismatch {
        let adifCallsigns: Set<String>
        let sessionCallsign: String
        let adifParks: Set<String>
        let sessionPark: String?
        /// Fields where ADIF data was missing and will use session defaults
        let missingFields: [String]
    }
}

// MARK: - Session Import

extension ImportService {
    /// Scan an ADIF file and return detected metadata without importing
    func scanADIF(from url: URL) throws -> DetectedMetadata {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFile
        }

        let records = try parser.parse(content)
        var callsigns = Set<String>()
        var parks = Set<String>()

        for record in records {
            if let call = record.stationCallsign ?? record.operatorCall {
                callsigns.insert(call.uppercased())
            }
            if let park = record.mySigInfo {
                if let sanitized = ParkReference.sanitizeMulti(park) {
                    parks.insert(sanitized)
                }
            }
        }

        return DetectedMetadata(
            callsigns: callsigns,
            parkReferences: parks,
            recordCount: records.count
        )
    }

    /// Compare detected ADIF metadata against a session and return mismatches
    func checkMetadataMismatch(
        detected: DetectedMetadata,
        session: LoggingSession
    ) -> MetadataMismatch? {
        let sessionCall = session.myCallsign.uppercased()
        let sessionPark = session.parkReference?.uppercased()

        let callsignMismatch = !detected.callsigns.isEmpty
            && !detected.callsigns.allSatisfy { $0 == sessionCall }
        let parkMismatch = hasParkMismatch(
            detected: detected.parkReferences,
            sessionPark: sessionPark
        )

        var missingFields: [String] = []
        if detected.callsigns.isEmpty {
            missingFields.append("callsign")
        }
        if detected.parkReferences.isEmpty, session.parkReference != nil {
            missingFields.append("park reference")
        }

        guard callsignMismatch || parkMismatch || !missingFields.isEmpty else {
            return nil
        }

        return MetadataMismatch(
            adifCallsigns: detected.callsigns,
            sessionCallsign: sessionCall,
            adifParks: detected.parkReferences,
            sessionPark: sessionPark,
            missingFields: missingFields
        )
    }

    /// Import an ADIF file into a specific session.
    /// When `overrideMetadata` is true, callsign/park are replaced with
    /// the session's values. When false, ADIF values are kept as-is
    /// (missing fields still default to the session's values via createQSO).
    func importADIFIntoSession(
        from url: URL,
        session: LoggingSession,
        overrideMetadata: Bool = false
    ) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        await performPreImportBackup()

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFile
        }

        // Skip filterForMultiOp — we're deliberately overriding
        // callsign/park with the session's values, so all records apply.
        let records = try parser.parse(content)
        let myCallsign = session.myCallsign
        let existingKeys = try fetchExistingDeduplicationKeys()

        var imported = 0
        var duplicates = 0
        var errors = 0
        var ledgerQSOs: [QSO] = []
        var touched: [QSO] = []

        for record in records {
            switch importRecordIntoSession(
                record, session: session,
                myCallsign: myCallsign, existingKeys: existingKeys,
                overrideMetadata: overrideMetadata
            ) {
            case let .imported(qso):
                ledgerQSOs.append(qso)
                touched.append(qso)
                imported += 1
            case let .updated(qsos):
                touched.append(contentsOf: qsos)
                duplicates += 1
            case nil: errors += 1
            }
        }

        session.qsoCount += imported
        try await commitImportedQSOs(touched)
        QSOLedger.appendBatch(ledgerQSOs)

        if imported > 0 || duplicates > 0 {
            NotificationCenter.default.post(
                name: .sessionQSOsDidChange,
                object: session.id
            )
        }

        let result = ImportResult(
            totalRecords: records.count, imported: imported,
            duplicates: duplicates, errors: errors, matched: 0
        )
        lastImportResult = result
        return result
    }

    // MARK: - Private Helpers

    private func hasParkMismatch(
        detected: Set<String>,
        sessionPark: String?
    ) -> Bool {
        guard !detected.isEmpty else {
            return false
        }
        guard let sessionPark else {
            return true
        }
        return !detected.allSatisfy { $0 == sessionPark }
    }

    private func performPreImportBackup() async {
        guard UserDefaults.standard.object(
            forKey: "autoBackupEnabled"
        ) as? Bool ?? true,
            let storeURL = modelContext.container
            .configurations.first?.url
        else {
            return
        }

        let count = BackupService.visibleQSOCount(in: modelContext.container)
        await BackupService.shared.snapshot(
            trigger: .preImport, storeURL: storeURL, qsoCount: count
        )
    }

    private func importRecordIntoSession(
        _ record: ADIFRecord,
        session: LoggingSession,
        myCallsign: String,
        existingKeys: Set<String>,
        overrideMetadata: Bool
    ) -> QSOProcessResult? {
        do {
            let qso = try createQSO(
                from: record, source: .adifFile, myCallsign: myCallsign
            )
            if overrideMetadata {
                qso.myCallsign = session.myCallsign
                if let park = session.parkReference {
                    qso.parkReference = park
                }
            }
            qso.loggingSessionId = session.id

            if existingKeys.contains(qso.deduplicationKey) {
                // Adopt existing QSO(s) into this session — return them so they ride
                // the cw-store-first batch.
                let adopted = adoptExistingQSO(
                    from: record,
                    session: session,
                    overrideMetadata: overrideMetadata
                )
                return .updated(adopted)
            }

            modelContext.insert(qso)
            createServicePresenceRecords(for: qso, importedFrom: nil)
            return .imported(qso)
        } catch {
            return nil // error
        }
    }

    /// Find existing QSO(s) by matching fields, assign them to the session,
    /// unhide if hidden, and optionally override metadata. Returns the mutated rows
    /// so the caller can route them through the cw-store-first import batch.
    private func adoptExistingQSO(
        from record: ADIFRecord,
        session: LoggingSession,
        overrideMetadata: Bool
    ) -> [QSO] {
        let call = record.callsign.uppercased()
        let bandLow = record.band.lowercased()
        guard let ts = record.timestamp else {
            return []
        }
        let tLo = ts.addingTimeInterval(-120)
        let tHi = ts.addingTimeInterval(120)

        let desc = BoundedDescriptor<QSO>(
            predicate: #Predicate {
                $0.callsign == call && $0.band == bandLow
                    && $0.timestamp >= tLo && $0.timestamp <= tHi
            },
            limit: 5
        )
        let matches = (try? modelContext.boundedFetch(desc)) ?? []
        for existing in matches {
            existing.loggingSessionId = session.id
            if existing.isHidden {
                existing.isHidden = false
            }
            if overrideMetadata {
                existing.myCallsign = session.myCallsign
                if let park = session.parkReference {
                    existing.parkReference = park
                }
            } else {
                // Restore ADIF metadata (may have been overridden
                // by a previous import)
                if let adifCall = record.myCallsign {
                    existing.myCallsign = adifCall
                }
                if let park = record.mySigInfo {
                    existing.parkReference =
                        ParkReference.sanitizeMulti(park)
                }
            }
        }
        return matches
    }
}
