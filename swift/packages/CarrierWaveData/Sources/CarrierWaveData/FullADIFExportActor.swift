// Full ADIF Export Actor
//
// Background actor that batch-fetches all QSOs from SwiftData and streams
// ADIF records to a temporary file. Designed for large logs (50-100k QSOs)
// without loading everything into memory at once.

import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - ADIFExportConfig

/// Branding configuration for ADIF export, parameterized per app.
public struct ADIFExportConfig: Sendable {
    // MARK: Lifecycle

    public init(
        appName: String,
        filenamePrefix: String,
        appFieldPrefix: String
    ) {
        self.appName = appName
        self.filenamePrefix = filenamePrefix
        self.appFieldPrefix = appFieldPrefix
    }

    // MARK: Public

    /// Display name used in ADIF header (e.g. "CarrierWave", "CWSweep").
    public let appName: String

    /// Prefix for the exported filename (e.g. "carrierwave_full_export").
    public let filenamePrefix: String

    /// Prefix for APP_* ADIF fields (e.g. "APP_CARRIERWAVE").
    public let appFieldPrefix: String
}

// MARK: - FullExportQSOSnapshot

/// Sendable snapshot of QSO data for full log ADIF export.
/// Superset of QSOExportSnapshot — includes app-specific metadata fields.
public struct FullExportQSOSnapshot: Sendable {
    // MARK: Lifecycle

    nonisolated public init(from qso: QSO) {
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
        contestName = qso.contestName
        contestSerialSent = qso.contestSerialSent
        contestSerialReceived = qso.contestSerialReceived
        contestExchangeSent = qso.contestExchangeSent
        contestExchangeReceived = qso.contestExchangeReceived
    }

    // MARK: Public

    public let callsign: String
    public let band: String
    public let mode: String
    public let frequency: Double?
    public let timestamp: Date
    public let rstSent: String?
    public let rstReceived: String?
    public let myCallsign: String
    public let myGrid: String?
    public let theirGrid: String?
    public let parkReference: String?
    public let theirParkReference: String?
    public let notes: String?
    public let name: String?
    public let qth: String?
    public let state: String?
    public let country: String?
    public let power: Int?
    public let myRig: String?
    public let sotaRef: String?
    public let wwffRef: String?
    public let dxcc: Int?
    public let qrzConfirmed: Bool
    public let lotwConfirmed: Bool
    public let lotwConfirmedDate: Date?
    public let aoaCode: String?
    public let stationProfileName: String?
    public let isActivityLogQSO: Bool
    public let importSourceRawValue: String
    public let loggingSessionId: UUID?
    public let contestName: String?
    public let contestSerialSent: Int?
    public let contestSerialReceived: Int?
    public let contestExchangeSent: String?
    public let contestExchangeReceived: String?

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

public struct FullExportProgressInfo: Sendable {
    public let processed: Int
    public let total: Int
}

// MARK: - FullExportResult

public struct FullExportResult: Sendable {
    public let fileURL: URL
    public let filename: String
    public let qsoCount: Int
    public let fileSizeBytes: Int64
}

// MARK: - FullADIFExportActor

public actor FullADIFExportActor {
    // MARK: Lifecycle

    public init(config: ADIFExportConfig) {
        self.config = config
    }

    // MARK: Public

    public func exportAllQSOs(
        container: ModelContainer,
        onProgress: @escaping @Sendable (FullExportProgressInfo) -> Void
    ) async throws -> FullExportResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let totalCount = try context.boundedCount(
            QSO.self,
            predicate: #Predicate { !$0.isHidden }
        )

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
        let attrs = try FileManager.default.attributesOfItem(
            atPath: fileURL.path
        )
        let fileSize = attrs[.size] as? Int64 ?? 0

        return FullExportResult(
            fileURL: fileURL,
            filename: filename,
            qsoCount: exportedCount,
            fileSizeBytes: fileSize
        )
    }

    // MARK: Internal

    let config: ADIFExportConfig

    // MARK: Private

    private static let fetchBatchSize = 1_000

    private func createTempFile() -> (url: URL, filename: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = dateFormatter.string(from: Date())
        let filename = "\(config.filenamePrefix)_\(dateStr).adi"
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
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate { !$0.isHidden },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)],
                limit: Self.fetchBatchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            let snapshots = batch
                .filter { !QSOMode.isMetadata($0.mode) }
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
}

// MARK: - Header & Record Building

extension FullADIFExportActor {
    private func buildHeader(totalCount: Int) -> String {
        var lines: [String] = []

        lines.append(
            "\(config.appName) full QSO log export (\(totalCount) QSOs)"
        )
        lines.append("")
        lines.append(formatField("ADIF_VER", "3.1.7"))
        lines.append(formatField("PROGRAMID", config.appName))
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                as? String ?? "1.0"
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

    private func buildFullRecord(
        _ snapshot: FullExportQSOSnapshot
    ) -> String {
        var fields: [String] = []

        appendCoreFields(to: &fields, snapshot: snapshot)
        appendStationFields(to: &fields, snapshot: snapshot)
        appendContactFields(to: &fields, snapshot: snapshot)
        appendActivationFields(to: &fields, snapshot: snapshot)
        appendConfirmationFields(to: &fields, snapshot: snapshot)
        appendAppFields(to: &fields, snapshot: snapshot)
        appendContestFields(to: &fields, snapshot: snapshot)

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
            fields.append(formatField(
                "FREQ", String(format: "%.6f", freq)
            ))
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
            fields.append(formatField(
                "STATION_CALLSIGN", snapshot.myCallsign
            ))
            fields.append(formatField("OPERATOR", snapshot.myCallsign))
        }
        if let theirGrid = snapshot.theirGrid, !theirGrid.isEmpty {
            fields.append(formatField(
                "GRIDSQUARE", theirGrid.uppercased()
            ))
        }
        if let myGrid = snapshot.myGrid, !myGrid.isEmpty {
            fields.append(formatField(
                "MY_GRIDSQUARE", myGrid.uppercased()
            ))
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

        if let theirPark = snapshot.theirParkReference,
           !theirPark.isEmpty
        {
            fields.append(formatField("SIG", "POTA"))
            fields.append(formatField("SIG_INFO", theirPark))
            fields.append(formatField("POTA_REF", theirPark))
        }

        if let sotaRef = snapshot.sotaRef, !sotaRef.isEmpty {
            fields.append(formatField("SOTA_REF", sotaRef))
            let hasPota = snapshot.parkReference != nil
                && snapshot.parkReference?.isEmpty == false
            if !hasPota {
                fields.append(formatField("MY_SIG", "SOTA"))
                fields.append(formatField("MY_SIG_INFO", sotaRef))
            }
        }

        if let wwffRef = snapshot.wwffRef, !wwffRef.isEmpty {
            fields.append(formatField("MY_WWFF_REF", wwffRef))
            let hasPota = snapshot.parkReference != nil
                && snapshot.parkReference?.isEmpty == false
            let hasSota = snapshot.sotaRef != nil
                && snapshot.sotaRef?.isEmpty == false
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
            fields.append(formatField("QRZCOM_QSO_UPLOAD_STATUS", "Y"))
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
}
