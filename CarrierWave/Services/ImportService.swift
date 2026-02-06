import CarrierWaveCore
import Combine
import Foundation
import SwiftData

// MARK: - ImportService

@MainActor
class ImportService: ObservableObject {
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

    enum QSOProcessResult { case updated, imported }

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    /// These should never be synced to any service
    static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    @Published var isImporting = false
    @Published var lastImportResult: ImportResult?

    let modelContext: ModelContext
    let parser = ADIFParser()

    func importADIF(from url: URL, source: ImportSource, myCallsign: String) async throws
        -> ImportResult
    {
        isImporting = true
        defer { isImporting = false }

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

        var imported = 0
        var duplicates = 0
        var errors = 0

        let existingKeys = try fetchExistingDeduplicationKeys()

        for record in records {
            do {
                let qso = try createQSO(from: record, source: source, myCallsign: myCallsign)

                if existingKeys.contains(qso.deduplicationKey) {
                    duplicates += 1
                    continue
                }

                modelContext.insert(qso)
                createServicePresenceRecords(for: qso, importedFrom: nil)
                imported += 1
            } catch {
                errors += 1
            }
        }

        try modelContext.save()

        let result = ImportResult(
            totalRecords: records.count, imported: imported,
            duplicates: duplicates, errors: errors, matched: 0
        )

        lastImportResult = result
        return result
    }

    func importFromLoFi(qsos: [(LoFiQso, LoFiOperation)]) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        let realQsos = qsos.filter { lofiQso, _ in
            !Self.metadataModes.contains(lofiQso.mode?.uppercased() ?? "")
        }

        let metadataEntries = qsos.filter { lofiQso, _ in
            Self.metadataModes.contains(lofiQso.mode?.uppercased() ?? "")
        }
        for (lofiQso, operation) in metadataEntries {
            storeActivationMetadata(from: lofiQso, operation: operation)
        }

        var imported = 0
        var duplicates = 0
        var errors = 0

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
                imported += 1
            } catch {
                errors += 1
            }
        }

        try modelContext.save()

        let result = ImportResult(
            totalRecords: realQsos.count, imported: imported,
            duplicates: duplicates, errors: errors, matched: 0
        )

        lastImportResult = result
        return result
    }

    func fetchExistingDeduplicationKeys() throws -> Set<String> {
        let descriptor = FetchDescriptor<QSO>()
        let qsos = try modelContext.fetch(descriptor)
        return Set(qsos.map(\.deduplicationKey))
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
        let isMetadata = Self.metadataModes.contains(qso.mode.uppercased())

        for service in ServiceType.allCases {
            if service == importedFrom {
                let presence = ServicePresence.downloaded(from: service, qso: qso)
                modelContext.insert(presence)
                qso.servicePresence.append(presence)
            } else if service.supportsUpload {
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

    // MARK: Private

    private func createQSO(from record: ADIFRecord, source: ImportSource, myCallsign: String) throws
        -> QSO
    {
        guard let timestamp = record.timestamp else {
            throw ImportError.missingTimestamp
        }

        return QSO(
            callsign: record.callsign, band: record.band, mode: record.mode,
            frequency: record.frequency, timestamp: timestamp,
            rstSent: record.rstSent, rstReceived: record.rstReceived,
            myCallsign: record.myCallsign ?? myCallsign, myGrid: record.myGridsquare,
            theirGrid: record.gridsquare, parkReference: record.mySigInfo,
            theirParkReference: record.sigInfo,
            notes: record.comment, importSource: source, rawADIF: record.rawADIF
        )
    }

    private func storeActivationMetadata(from lofiQso: LoFiQso, operation: LoFiOperation) {
        guard let mode = lofiQso.mode?.uppercased() else {
            return
        }
        guard
            let parkRef = operation.refs.first(where: { $0.refType == "potaActivation" })?.reference
        else {
            return
        }

        let timestamp: Date =
            if let startMillis = operation.startAtMillisMin {
                Date(timeIntervalSince1970: Double(startMillis) / 1_000.0)
            } else if let qsoTimestamp = lofiQso.timestamp {
                qsoTimestamp
            } else {
                Date() // Fallback to now if no timestamp available
            }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.startOfDay(for: timestamp)

        let descriptor = FetchDescriptor<ActivationMetadata>()
        let allMetadata = (try? modelContext.fetch(descriptor)) ?? []
        let existing = allMetadata.first { $0.parkReference == parkRef && $0.date == date }

        let metadata: ActivationMetadata
        if let existing {
            metadata = existing
        } else {
            metadata = ActivationMetadata(parkReference: parkRef, date: date)
            modelContext.insert(metadata)
        }

        let value = lofiQso.notes
        if mode == "WEATHER" {
            metadata.weather = value
        } else if mode == "SOLAR" {
            metadata.solarConditions = value
        }
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
