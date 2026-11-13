import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - ImportService

@Observable
@MainActor
class ImportService {
    // MARK: Lifecycle

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: Internal

    struct ImportResult {
        let totalRecords: Int
        let imported: Int
        let duplicates: Int
        let errors: Int
        let matched: Int
    }

    enum QSOProcessResult {
        /// One or more existing QSOs were mutated in place (QRZ/POTA enrichment, or
        /// session adoption). Carries the touched rows so they ride the cw-store-first
        /// batch instead of being swallowed by a suppressed seam save.
        case updated([QSO])
        case imported(QSO)
    }

    var isImporting = false
    var lastImportResult: ImportResult?

    let modelContext: ModelContext
    let parser = ADIFParser()

    func importADIF(from url: URL, source: ImportSource, myCallsign: String) async throws
        -> ImportResult
    {
        isImporting = true
        defer { isImporting = false }

        // Pre-import backup
        if UserDefaults.standard.object(
            forKey: "autoBackupEnabled"
        ) as? Bool ?? true,
            let storeURL = modelContext.container
            .configurations.first?.url
        {
            let count = BackupService.visibleQSOCount(
                in: modelContext.container
            )
            await BackupService.shared.snapshot(
                trigger: .preImport, storeURL: storeURL,
                qsoCount: count
            )
        }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFile
        }

        return try await importADIF(content: content, source: source, myCallsign: myCallsign)
    }

    func importADIF(content: String, source: ImportSource, myCallsign: String) async throws
        -> ImportResult
    {
        isImporting = true
        defer { isImporting = false }

        let records = try parser.parse(content)
        let filtered = filterForMultiOp(records: records, myCallsign: myCallsign)

        var imported = 0
        var duplicates = 0
        var errors = 0
        let skipped = records.count - filtered.count
        var ledgerQSOs: [QSO] = []

        let existingKeys = try fetchExistingDeduplicationKeys()

        for record in filtered {
            do {
                let qso = try createQSO(from: record, source: source, myCallsign: myCallsign)

                if existingKeys.contains(qso.deduplicationKey) {
                    duplicates += 1
                    continue
                }

                modelContext.insert(qso)
                createServicePresenceRecords(for: qso, importedFrom: nil)
                ledgerQSOs.append(qso)
                imported += 1
            } catch {
                errors += 1
            }
        }

        try await commitImportedQSOs(ledgerQSOs)
        QSOLedger.appendBatch(ledgerQSOs)

        let result = ImportResult(
            totalRecords: records.count, imported: imported,
            duplicates: duplicates, errors: errors + skipped, matched: 0
        )

        lastImportResult = result
        return result
    }

    func importFromLoFi(qsos: [(LoFiQso, LoFiOperation)]) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        let realQsos = qsos.filter { lofiQso, _ in
            !(lofiQso.mode.map { QSOMode.isMetadata($0) } ?? false)
        }

        let metadataEntries = qsos.filter { lofiQso, _ in
            lofiQso.mode.map { QSOMode.isMetadata($0) } ?? false
        }
        var stagedMetadata: [ActivationMetadata] = []
        for (lofiQso, operation) in metadataEntries {
            if let metadata = storeActivationMetadata(from: lofiQso, operation: operation) {
                stagedMetadata.append(metadata)
            }
        }
        // Route the metadata canonically NOW, before any real QSOs are inserted, so
        // it can't be swallowed by a later suppressed QSO-chunk save in `.on` mode.
        if !stagedMetadata.isEmpty {
            try? EntityWriteSink.commitUpsert(stagedMetadata, in: modelContext)
        }

        var imported = 0
        var duplicates = 0
        var errors = 0
        var ledgerQSOs: [QSO] = []

        let existingKeys = try fetchExistingDeduplicationKeys()

        for (lofiQso, operation) in realQsos {
            do {
                let qso = try createQSO(from: lofiQso, operation: operation)

                if existingKeys.contains(qso.deduplicationKey) {
                    duplicates += 1
                    continue
                }

                modelContext.insert(qso)
                createServicePresenceRecords(for: qso, importedFrom: .lofi)
                ledgerQSOs.append(qso)
                imported += 1
            } catch {
                errors += 1
            }
        }

        try await commitImportedQSOs(ledgerQSOs)
        QSOLedger.appendBatch(ledgerQSOs)

        let result = ImportResult(
            totalRecords: realQsos.count, imported: imported,
            duplicates: duplicates, errors: errors, matched: 0
        )

        lastImportResult = result
        return result
    }

    /// Fetch all deduplication keys using batched reads to avoid loading
    /// every QSO object into memory at once (~400 MB+ at 100K QSOs).
    func fetchExistingDeduplicationKeys() throws -> Set<String> {
        let batchSize = 1_000
        var offset = 0
        var keys = Set<String>()

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
                keys.insert(qso.deduplicationKey)
            }

            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }

        return keys
    }

    /// Persist a freshly-imported batch of QSOs through `QSOWriteSink` so cw-store is
    /// canonical/cw-store-first in `on` mode (plain save in `off`/`shadow`, where the
    /// unsuppressed mirror dual-writes in `shadow`). Commits in bounded chunks with a
    /// `Task.yield()` between them so a large import can't block the main thread on one
    /// giant cw-store write + save. Only pure-insert paths (top-level ADIF/LoFi) use this
    /// — paths that mutate existing rows in place (session adoption, QRZ/POTA redownload)
    /// stay mirror-followed because a suppressed seam save would swallow those updates.
    /// A trailing save flushes any non-QSO pending changes (e.g. LoFi activation metadata)
    /// that aren't carried by a chunk.
    func commitImportedQSOs(_ qsos: [QSO]) async throws {
        let chunkSize = 500
        var index = 0
        while index < qsos.count {
            let end = min(index + chunkSize, qsos.count)
            try QSOWriteSink.commitUpsertBatch(Array(qsos[index ..< end]), in: modelContext)
            index = end
            if index < qsos.count {
                await Task.yield()
            }
        }
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func createServicePresenceRecords(for qso: QSO, importedFrom: ServiceType?) {
        // Only create upload markers for QSOs matching the user's primary callsign.
        // QSOs from previous callsigns are kept locally but won't sync to services.
        let primaryCallsign = CallsignAliasService.shared.getCurrentCallsign()?.uppercased()
        let qsoCallsign = qso.myCallsign.uppercased()
        let matchesPrimary =
            qsoCallsign.isEmpty || primaryCallsign == nil
                || qsoCallsign == primaryCallsign

        // Skip upload markers for metadata pseudo-modes (WEATHER, SOLAR, NOTE)
        // These are activation metadata from Ham2K PoLo, not actual QSOs
        let isMetadata = QSOMode.isMetadata(qso.mode)

        // Only mark needsUpload for services that are actually configured
        let configuredServices = CarrierWaveData.ServiceConfiguration.configuredUploadServices()

        for service in ServiceType.allCases {
            if service == importedFrom {
                let presence = ServicePresence.downloaded(from: service, qso: qso)
                modelContext.insert(presence)
                qso.servicePresence.append(presence)
            } else if service.supportsUpload, configuredServices.contains(service) {
                // Skip upload markers for metadata pseudo-modes
                guard !isMetadata else {
                    continue
                }
                // Skip upload markers for QSOs not matching primary callsign
                guard matchesPrimary else {
                    continue
                }
                // POTA uploads only apply to QSOs where user was activating from a park
                if service == .pota, qso.parkReference?.isEmpty ?? true {
                    continue
                }
                let presence = ServicePresence.needsUpload(to: service, qso: qso)
                modelContext.insert(presence)
                qso.servicePresence.append(presence)
            }
        }
    }

    /// Filter records for multi-op import: if file contains OPERATOR/STATION_CALLSIGN
    /// fields with values differing from user's callsign, keep only matching QSOs.
    /// Files without these fields or where all values match import unchanged.
    func filterForMultiOp(
        records: [ADIFRecord],
        myCallsign: String
    ) -> [ADIFRecord] {
        let normalizedMy = stripPortableSuffix(myCallsign.uppercased())

        let hasMultiOp = records.contains { record in
            let opCall = record.operatorCall?.uppercased()
            let stCall = record.stationCallsign?.uppercased()
            let opNorm = opCall.map { stripPortableSuffix($0) }
            let stNorm = stCall.map { stripPortableSuffix($0) }
            return (opNorm != nil && opNorm != normalizedMy)
                || (stNorm != nil && stNorm != normalizedMy)
        }

        guard hasMultiOp else {
            return records
        }

        return records.filter { record in
            let opNorm = record.operatorCall.map { stripPortableSuffix($0.uppercased()) }
            let stNorm = record.stationCallsign.map { stripPortableSuffix($0.uppercased()) }
            return opNorm == normalizedMy || stNorm == normalizedMy
                || (opNorm == nil && stNorm == nil)
        }
    }

    func createQSO(from record: ADIFRecord, source: ImportSource, myCallsign: String) throws
        -> QSO
    {
        guard let timestamp = record.timestamp else {
            throw ImportError.missingTimestamp
        }

        // MY_SIG_INFO → my activation park
        var parkReference = record.mySigInfo.flatMap { ParkReference.sanitizeMulti($0) }
        var theirParkReference = record.sigInfo.flatMap { ParkReference.sanitize($0) }

        // Apply user's comment park action for park refs found in COMMENT
        let commentRef = record.comment.flatMap { ParkReference.extractFromFreeText($0) }
        if let commentRef {
            switch CommentParkAction.current {
            case .ignore:
                break
            case .theirPark:
                theirParkReference = theirParkReference ?? commentRef
            case .myPark:
                parkReference = parkReference ?? commentRef
            }
        }

        // WWFF references: prefer dedicated MY_WWFF_REF field, fall back to MY_SIG_INFO when SIG=WWFF
        let wwffRef = record.myWwffRef

        let qso = QSO(
            callsign: record.callsign, band: record.band, mode: record.mode,
            frequency: record.frequency, timestamp: timestamp,
            rstSent: record.rstSent, rstReceived: record.rstReceived,
            myCallsign: record.myCallsign ?? myCallsign, myGrid: record.myGridsquare,
            theirGrid: record.gridsquare,
            parkReference: parkReference,
            theirParkReference: theirParkReference,
            notes: record.comment, importSource: source, rawADIF: record.rawADIF,
            name: record.name,
            qth: record.qth,
            state: record.state,
            wwffRef: wwffRef,
            satName: record.satName,
            propMode: record.propMode
        )
        qso.stationCallsign = record.stationCallsign
        return qso
    }

    // MARK: Private

    /// Strip portable suffixes like /P, /M, /4 from a callsign for matching
    private func stripPortableSuffix(_ callsign: String) -> String {
        guard let slashRange = callsign.range(of: "/", options: .backwards) else {
            return callsign
        }
        let suffix = callsign[slashRange.upperBound...]
        if suffix.count <= 2 {
            return String(callsign[..<slashRange.lowerBound])
        }
        return callsign
    }

    private func createQSO(from lofiQso: LoFiQso, operation: LoFiOperation) throws -> QSO {
        guard let callsign = lofiQso.theirCall else {
            throw ImportError.parseError("Missing their callsign")
        }
        guard let band = lofiQso.band else {
            throw ImportError.parseError("Missing band")
        }
        guard let mode = lofiQso.mode else {
            throw ImportError.parseError("Missing mode")
        }

        let myCallsign = lofiQso.ourCall ?? operation.stationCall
        let parkRef = lofiQso.myPotaRef(from: operation.refs)
        let qsoTimestamp = lofiQso.timestamp ?? Date()

        return QSO(
            callsign: callsign, band: band, mode: mode, frequency: lofiQso.freqMHz,
            timestamp: qsoTimestamp, rstSent: lofiQso.rstSent, rstReceived: lofiQso.rstRcvd,
            myCallsign: myCallsign, myGrid: operation.grid, theirGrid: lofiQso.theirGrid,
            parkReference: parkRef.flatMap { ParkReference.sanitizeMulti($0) },
            notes: lofiQso.notes, importSource: .lofi
        )
    }
}

// QRZ and POTA import methods are in ImportService+External.swift
// Session-targeted import is in ImportService+Session.swift

// MARK: - LoFi Metadata

private extension ImportService {
    /// Stage activation metadata from a LoFi metadata pseudo-QSO. Does NOT save —
    /// returns the touched `ActivationMetadata` so the caller can route it through
    /// the seam before inserting real QSOs (a later suppressed QSO-chunk save would
    /// otherwise swallow this dirty row out of cw-store in `.on` mode). `nil` when
    /// nothing applies.
    @discardableResult
    func storeActivationMetadata(
        from lofiQso: LoFiQso, operation: LoFiOperation
    ) -> ActivationMetadata? {
        guard let mode = lofiQso.mode?.uppercased() else {
            return nil
        }
        guard let parkRef = operation.refs
            .first(where: { $0.refType == "potaActivation" })?
            .reference
        else {
            return nil
        }

        let timestamp: Date =
            if let startMillis = operation.startAtMillisMin {
                Date(
                    timeIntervalSince1970: Double(startMillis) / 1_000.0
                )
            } else if let qsoTimestamp = lofiQso.timestamp {
                qsoTimestamp
            } else {
                Date()
            }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.startOfDay(for: timestamp)

        var descriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate {
                $0.parkReference == parkRef && $0.date == date
            }
        )
        descriptor.fetchLimit = 1
        let existing = (try? modelContext.fetch(descriptor))?.first

        let metadata: ActivationMetadata
        if let existing {
            metadata = existing
        } else {
            metadata = ActivationMetadata(
                parkReference: parkRef, date: date
            )
            metadata.cloudDirtyFlag = true
            modelContext.insert(metadata)
        }

        let value = lofiQso.notes
        if mode == "WEATHER" {
            metadata.weather = value
        } else if mode == "SOLAR" {
            metadata.solarConditions = value
        }
        metadata.cloudDirtyFlag = true
        return metadata
    }
}

// MARK: - ImportError

enum ImportError: Error, LocalizedError {
    case invalidFile
    case missingTimestamp
    case parseError(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidFile: "Could not read the ADIF file"
        case .missingTimestamp: "QSO record missing date/time"
        case let .parseError(message): "Parse error: \(message)"
        }
    }
}
