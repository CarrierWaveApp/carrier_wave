// Full ADIF Export Actor
//
// Background actor that batch-fetches all QSOs from SwiftData and streams
// ADIF records to a temporary file. Designed for large logs (50-100k QSOs)
// without loading everything into memory at once.

import CarrierWaveData
import Foundation
import SwiftData

// MARK: - FullExportQSOSnapshot

/// Sendable snapshot of QSO data for full log ADIF export.
/// Superset of QSOExportSnapshot — includes app-specific metadata fields.
struct FullExportQSOSnapshot: Sendable {
    // MARK: Lifecycle

    nonisolated init(from qso: QSO) {
        callsign = Self.asciiSafe(qso.callsign)
        band = qso.band
        mode = qso.mode
        frequency = qso.frequency
        timestamp = qso.timestamp
        rstSent = qso.rstSent
        rstReceived = qso.rstReceived
        myCallsign = Self.asciiSafe(qso.myCallsign)
        myGrid = qso.myGrid
        theirGrid = qso.theirGrid
        parkReference = qso.parkReference
        theirParkReference = qso.theirParkReference
        notes = qso.notes.map { Self.asciiSafe($0) }
        name = qso.name.map { Self.asciiSafe($0) }
        qth = qso.qth.map { Self.asciiSafe($0) }
        state = qso.state
        country = qso.country.map { Self.asciiSafe($0) }
        power = qso.power
        myRig = qso.myRig.map { Self.asciiSafe($0) }
        sotaRef = qso.sotaRef
        wwffRef = qso.wwffRef
        dxcc = qso.dxcc
        qrzConfirmed = qso.qrzConfirmed
        lotwConfirmed = qso.lotwConfirmed
        lotwConfirmedDate = qso.lotwConfirmedDate
        aoaCode = qso.aoaCode
        stationProfileName = qso.stationProfileName
        isActivityLogQSO = qso.isActivityLogQSO
        importSourceRawValue = qso.importSourceRawValue
        loggingSessionId = qso.loggingSessionId
    }

    // MARK: Internal

    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let theirParkReference: String?
    let notes: String?
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let power: Int?
    let myRig: String?
    let sotaRef: String?
    let wwffRef: String?
    let dxcc: Int?
    let qrzConfirmed: Bool
    let lotwConfirmed: Bool
    let lotwConfirmedDate: Date?
    let aoaCode: String?
    let stationProfileName: String?
    let isActivityLogQSO: Bool
    let importSourceRawValue: String
    let loggingSessionId: UUID?

    // MARK: Private

    /// Strip non-ASCII characters, transliterating accented chars first.
    nonisolated private static func asciiSafe(_ string: String) -> String {
        let transliterated =
            string.applyingTransform(.toLatin, reverse: false)
                ?? string
        return String(transliterated.unicodeScalars.filter {
            $0.value >= 0x20 && $0.value <= 0x7E
        })
    }
}

// MARK: - FullExportProgressInfo

struct FullExportProgressInfo: Sendable {
    let processed: Int
    let total: Int
}

// MARK: - FullExportResult

struct FullExportResult: Sendable {
    let fileURL: URL
    let filename: String
    let qsoCount: Int
    let fileSizeBytes: Int64
}

// MARK: - FullADIFExportActor

actor FullADIFExportActor {
    // MARK: Internal

    func exportAllQSOs(
        container: ModelContainer,
        onProgress: @escaping @Sendable (FullExportProgressInfo) -> Void
    ) async throws -> FullExportResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var countDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { !$0.isHidden }
        )
        countDescriptor.propertiesToFetch = []
        let totalCount = try context.fetchCount(countDescriptor)

        let (fileURL, filename) = createTempFile()
        try? FileManager.default.removeItem(at: fileURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? fileHandle.close() }

        fileHandle.write(Data(buildHeader(totalCount: totalCount).utf8))

        let exportedCount = try await writeBatches(
            context: context,
            totalCount: totalCount,
            fileHandle: fileHandle,
            onProgress: onProgress
        )

        try fileHandle.synchronize()
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attrs[.size] as? Int64 ?? 0

        return FullExportResult(
            fileURL: fileURL,
            filename: filename,
            qsoCount: exportedCount,
            fileSizeBytes: fileSize
        )
    }

    // MARK: Private

    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]
    private static let fetchBatchSize = 1_000

    private func createTempFile() -> (url: URL, filename: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = dateFormatter.string(from: Date())
        let filename = "carrierwave_full_export_\(dateStr).adi"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        return (url, filename)
    }

    private func writeBatches(
        context: ModelContext,
        totalCount: Int,
        fileHandle: FileHandle,
        onProgress: @escaping @Sendable (FullExportProgressInfo) -> Void
    ) async throws -> Int {
        var offset = 0
        var exportedCount = 0

        while offset < totalCount {
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { !$0.isHidden },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.fetchBatchSize

            let batch = try context.fetch(descriptor)
            if batch.isEmpty {
                break
            }

            let snapshots = batch
                .filter { !Self.metadataModes.contains($0.mode.uppercased()) }
                .map { FullExportQSOSnapshot(from: $0) }

            var batchText = ""
            batchText.reserveCapacity(snapshots.count * 300)
            for snapshot in snapshots {
                batchText.append(buildFullRecord(snapshot))
                batchText.append("\n")
            }

            fileHandle.write(Data(batchText.utf8))
            exportedCount += snapshots.count
            offset += batch.count

            onProgress(FullExportProgressInfo(
                processed: offset,
                total: totalCount
            ))
            await Task.yield()
        }

        return exportedCount
    }

    // MARK: - Header

    private func buildHeader(totalCount: Int) -> String {
        var lines: [String] = []

        lines.append("Carrier Wave full QSO log export (\(totalCount) QSOs)")
        lines.append("")
        lines.append(formatField("ADIF_VER", "3.1.6"))
        lines.append(formatField("PROGRAMID", "CarrierWave"))
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                ?? "1.0"
        lines.append(formatField("PROGRAMVERSION", version))

        let timestampFmt = DateFormatter()
        timestampFmt.dateFormat = "yyyyMMdd HHmmss"
        timestampFmt.timeZone = TimeZone(identifier: "UTC")
        lines.append(formatField(
            "CREATED_TIMESTAMP",
            timestampFmt.string(from: Date())
        ))
        lines.append("<EOH>")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Record Building

    private func buildFullRecord(_ snapshot: FullExportQSOSnapshot) -> String {
        var fields: [String] = []

        appendCoreFields(to: &fields, snapshot: snapshot)
        appendStationFields(to: &fields, snapshot: snapshot)
        appendContactFields(to: &fields, snapshot: snapshot)
        appendActivationFields(to: &fields, snapshot: snapshot)
        appendConfirmationFields(to: &fields, snapshot: snapshot)
        appendAppFields(to: &fields, snapshot: snapshot)

        if let notes = snapshot.notes, !notes.isEmpty {
            let cleaned = ParkReference.stripFromFreeText(notes) ?? notes
            fields.append(formatField("COMMENT", cleaned))
        }

        return fields.joined() + "<EOR>"
    }

    private func appendCoreFields(
        to fields: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        fields.append(formatField("CALL", snapshot.callsign))
        fields.append(formatField("BAND", snapshot.band))
        let modeSubmode = ModeEquivalence.adifModeSubmode(snapshot.mode)
        fields.append(formatField("MODE", modeSubmode.mode))
        if let submode = modeSubmode.submode {
            fields.append(formatField("SUBMODE", submode))
        }
        if let freq = snapshot.frequency {
            fields.append(formatField("FREQ", String(format: "%.6f", freq)))
        }

        let dateFmt = DateFormatter()
        dateFmt.timeZone = TimeZone(identifier: "UTC")
        dateFmt.dateFormat = "yyyyMMdd"
        fields.append(formatField(
            "QSO_DATE",
            dateFmt.string(from: snapshot.timestamp)
        ))
        dateFmt.dateFormat = "HHmmss"
        fields.append(formatField(
            "TIME_ON",
            dateFmt.string(from: snapshot.timestamp)
        ))

        if let rstRcvd = snapshot.rstReceived, !rstRcvd.isEmpty {
            fields.append(formatField("RST_RCVD", rstRcvd))
        }
        if let rstSent = snapshot.rstSent, !rstSent.isEmpty {
            fields.append(formatField("RST_SENT", rstSent))
        }
    }

    private func appendStationFields(
        to fields: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        if !snapshot.myCallsign.isEmpty {
            fields.append(formatField("STATION_CALLSIGN", snapshot.myCallsign))
            fields.append(formatField("OPERATOR", snapshot.myCallsign))
        }
        if let theirGrid = snapshot.theirGrid, !theirGrid.isEmpty {
            fields.append(formatField("GRIDSQUARE", theirGrid.uppercased()))
        }
        if let myGrid = snapshot.myGrid, !myGrid.isEmpty {
            fields.append(formatField("MY_GRIDSQUARE", myGrid.uppercased()))
        }
    }

    private func appendContactFields(
        to fields: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        if let name = snapshot.name, !name.isEmpty {
            fields.append(formatField("NAME", name))
        }
        if let qth = snapshot.qth, !qth.isEmpty {
            fields.append(formatField("QTH", qth))
        }
        if let state = snapshot.state, !state.isEmpty {
            fields.append(formatField("STATE", state))
        }
        if let country = snapshot.country, !country.isEmpty {
            fields.append(formatField("COUNTRY", country))
        }
        if let dxcc = snapshot.dxcc {
            fields.append(formatField("DXCC", String(dxcc)))
        }
        if let power = snapshot.power {
            fields.append(formatField("TX_PWR", String(power)))
        }
        if let myRig = snapshot.myRig, !myRig.isEmpty {
            fields.append(formatField("MY_RIG", myRig))
        }
    }

    private func appendActivationFields(
        to fields: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        if let parkRef = snapshot.parkReference, !parkRef.isEmpty {
            fields.append(formatField("MY_SIG", "POTA"))
            fields.append(formatField("MY_SIG_INFO", parkRef))
            fields.append(formatField("MY_POTA_REF", parkRef))
        }

        if let theirPark = snapshot.theirParkReference, !theirPark.isEmpty {
            fields.append(formatField("SIG", "POTA"))
            fields.append(formatField("SIG_INFO", theirPark))
            fields.append(formatField("POTA_REF", theirPark))
        }

        if let sotaRef = snapshot.sotaRef, !sotaRef.isEmpty {
            fields.append(formatField("SOTA_REF", sotaRef))
            // If no POTA park ref, use SOTA as primary SIG
            if snapshot.parkReference == nil || snapshot.parkReference?.isEmpty == true {
                fields.append(formatField("MY_SIG", "SOTA"))
                fields.append(formatField("MY_SIG_INFO", sotaRef))
            }
        }

        if let wwffRef = snapshot.wwffRef, !wwffRef.isEmpty {
            fields.append(formatField("MY_WWFF_REF", wwffRef))
            // If no POTA or SOTA ref, use WWFF as primary SIG
            let hasPota = snapshot.parkReference != nil && snapshot.parkReference?.isEmpty == false
            let hasSota = snapshot.sotaRef != nil && snapshot.sotaRef?.isEmpty == false
            if !hasPota, !hasSota {
                fields.append(formatField("MY_SIG", "WWFF"))
                fields.append(formatField("MY_SIG_INFO", wwffRef))
            }
        }
    }

    private func appendConfirmationFields(
        to fields: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        if snapshot.qrzConfirmed {
            fields.append(formatField("QRZ_QSO_UPLOAD_STATUS", "Y"))
        }
        if snapshot.lotwConfirmed {
            fields.append(formatField("LOTW_QSL_RCVD", "Y"))
            if let lotwDate = snapshot.lotwConfirmedDate {
                let dateFmt = DateFormatter()
                dateFmt.timeZone = TimeZone(identifier: "UTC")
                dateFmt.dateFormat = "yyyyMMdd"
                fields.append(formatField(
                    "LOTW_QSLRDATE",
                    dateFmt.string(from: lotwDate)
                ))
            }
        }
    }

    private func appendAppFields(
        to fields: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        fields.append(formatField(
            "APP_CARRIERWAVE_IMPORT_SOURCE",
            snapshot.importSourceRawValue
        ))

        if snapshot.isActivityLogQSO {
            fields.append(formatField(
                "APP_CARRIERWAVE_ACTIVITY_LOG_QSO",
                "Y"
            ))
        }

        if let aoaCode = snapshot.aoaCode, !aoaCode.isEmpty {
            fields.append(formatField("APP_CARRIERWAVE_AOA_CODE", aoaCode))
        }

        if let profile = snapshot.stationProfileName, !profile.isEmpty {
            fields.append(formatField(
                "APP_CARRIERWAVE_STATION_PROFILE",
                profile
            ))
        }

        if let sessionId = snapshot.loggingSessionId {
            fields.append(formatField(
                "APP_CARRIERWAVE_LOGGING_SESSION_ID",
                sessionId.uuidString
            ))
        }
    }

    /// Format a single ADIF field: <NAME:length>value
    private func formatField(_ name: String, _ value: String) -> String {
        "<\(name.uppercased()):\(value.count)>\(value)"
    }
}
