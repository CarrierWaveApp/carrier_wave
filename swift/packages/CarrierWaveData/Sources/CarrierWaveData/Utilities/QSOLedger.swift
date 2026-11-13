import CarrierWaveCore
import Foundation
import OSLog

// MARK: - QSOLedger

/// Append-only ADIF files that record every QSO outside SwiftData.
///
/// This is a safety net: if the database is destroyed (migration
/// failure, corrupt WAL, snapshot overwrite), the ledger survives
/// because it lives in `Documents/QSOLedger/` and is never touched
/// by ModelContainer, backup pruning, or sync.
///
/// Files are rotated monthly (UTC) so no single file grows beyond
/// a few MB even for heavy operators (200K+ QSOs). Each file is a
/// valid ADIF log importable by Carrier Wave or any ham radio app.
public enum QSOLedger {
    // MARK: Public

    /// Supported ledger file extensions.
    public static let ledgerExtensions: Set<String> = ["adi", "qsonl"]

    /// Directory containing all monthly ledger files.
    public static var directoryURL: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        return docs.appendingPathComponent("QSOLedger")
    }

    /// All ledger files sorted newest-first.
    public static func allFiles() -> [LedgerFile] {
        let fm = FileManager.default
        let dir = directoryURL
        guard let urls = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return []
        }
        return urls
            .filter { ledgerExtensions.contains($0.pathExtension) }
            .compactMap { url -> LedgerFile? in
                let attrs = try? fm.attributesOfItem(
                    atPath: url.path
                )
                let size = (attrs?[.size] as? Int64) ?? 0
                return LedgerFile(url: url, sizeBytes: size)
            }
            .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    /// Append a single QSO record to the current month's ledger.
    /// Safe to call from any thread — internally serialized.
    public static func append(_ qso: QSO) {
        let adifRecord = ADIFRecordBuilder.build(from: qso)
        let qsonRecord = QSONRecordBuilder.build(from: qso)
        writeRecord(
            adif: adifRecord, qson: qsonRecord,
            for: qso.timestamp
        )
    }

    /// Append multiple QSO records (e.g. after a batch import).
    public static func appendBatch(_ qsos: [QSO]) {
        guard !qsos.isEmpty else {
            return
        }
        // Group by month so each record lands in the correct file
        var adifByMonth: [String: [String]] = [:]
        var qsonByMonth: [String: [String]] = [:]
        for qso in qsos {
            let key = monthKey(for: qso.timestamp)
            adifByMonth[key, default: []].append(
                ADIFRecordBuilder.build(from: qso)
            )
            qsonByMonth[key, default: []].append(
                QSONRecordBuilder.build(from: qso)
            )
        }
        lock.withLock {
            for (month, records) in adifByMonth {
                let url = fileURL(forMonth: month)
                ensureFile(at: url, month: month)
                appendToFile(
                    url: url,
                    text: records.joined(separator: "\n") + "\n"
                )
            }
            for (month, records) in qsonByMonth {
                let url = qsonFileURL(forMonth: month)
                ensureQSONFile(at: url)
                appendToFile(
                    url: url,
                    text: records.joined(separator: "\n") + "\n"
                )
            }
        }
    }

    /// Move legacy single-file ledger into the monthly directory.
    /// Call once on app launch; no-ops if already migrated.
    public static func migrateIfNeeded() {
        let fm = FileManager.default
        let docs = fm.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let legacyURL = docs.appendingPathComponent("qso-ledger.adi")
        guard fm.fileExists(atPath: legacyURL.path) else {
            return
        }
        try? fm.createDirectory(
            at: directoryURL, withIntermediateDirectories: true
        )
        // Move into directory as "legacy.adi" so it sorts last
        let destURL = directoryURL.appendingPathComponent(
            "legacy.adi"
        )
        try? fm.moveItem(at: legacyURL, to: destURL)
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: "com.carrierwave", category: "QSOLedger"
    )

    private static let lock = NSLock()

    private static let monthFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM"
        return fmt
    }()

    private static func monthKey(for date: Date) -> String {
        monthFmt.string(from: date)
    }

    private static func fileURL(forMonth month: String) -> URL {
        directoryURL.appendingPathComponent("\(month).adi")
    }

    private static func qsonFileURL(forMonth month: String) -> URL {
        directoryURL.appendingPathComponent("\(month).qsonl")
    }

    private static func writeRecord(
        adif: String, qson: String, for date: Date
    ) {
        let month = monthKey(for: date)
        lock.withLock {
            let adiURL = fileURL(forMonth: month)
            ensureFile(at: adiURL, month: month)
            appendToFile(url: adiURL, text: adif + "\n")

            let qsonURL = qsonFileURL(forMonth: month)
            ensureQSONFile(at: qsonURL)
            appendToFile(url: qsonURL, text: qson + "\n")
        }
    }

    private static func ensureFile(at url: URL, month: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return
        }
        try? fm.createDirectory(
            at: directoryURL, withIntermediateDirectories: true
        )
        let header = buildHeader(month: month)
        fm.createFile(
            atPath: url.path, contents: Data(header.utf8)
        )
    }

    private static func ensureQSONFile(at url: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return
        }
        try? fm.createDirectory(
            at: directoryURL, withIntermediateDirectories: true
        )
        fm.createFile(atPath: url.path, contents: nil)
    }

    private static func appendToFile(url: URL, text: String) {
        guard let handle = try? FileHandle(forWritingTo: url)
        else {
            logger.error(
                "Cannot open ledger: \(url.lastPathComponent)"
            )
            return
        }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
    }

    private static func buildHeader(month: String) -> String {
        [
            "Carrier Wave QSO Safety Ledger (\(month))",
            "",
            ADIFRecordBuilder.field("ADIF_VER", "3.1.7"),
            ADIFRecordBuilder.field("PROGRAMID", "CarrierWave"),
            "<EOH>",
            "",
        ].joined(separator: "\n")
    }
}

// MARK: - LedgerFile

public struct LedgerFile: Identifiable, Sendable {
    public let url: URL
    public let sizeBytes: Int64

    public var id: String {
        url.lastPathComponent
    }

    public var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Human-readable format label for the ledger file
    /// (e.g. "ADIF", "QSON") based on the file extension.
    public var format: String {
        switch url.pathExtension {
        case "adi",
             "adif": "ADIF"
        case "qsonl",
             "qson": "QSON"
        default: url.pathExtension.uppercased()
        }
    }
}

// MARK: - ADIFRecordBuilder

/// Builds ADIF record strings from QSO model objects.
/// Extracted to keep QSOLedger under line limits.
enum ADIFRecordBuilder {
    // MARK: Internal

    static let dateFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyyMMdd"
        return fmt
    }()

    static let timeFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "HHmmss"
        return fmt
    }()

    static func build(from qso: QSO) -> String {
        var fields: [String] = []
        appendCoreFields(to: &fields, qso: qso)
        appendStationFields(to: &fields, qso: qso)
        appendActivationFields(to: &fields, qso: qso)
        appendContactFields(to: &fields, qso: qso)
        return fields.joined() + "<EOR>"
    }

    static func field(
        _ name: String, _ value: String
    ) -> String {
        "<\(name.uppercased()):\(value.utf8.count)>\(value)"
    }

    // MARK: Private

    private static func appendCoreFields(
        to fields: inout [String], qso: QSO
    ) {
        fields.append(field("CALL", qso.callsign))
        fields.append(field("BAND", qso.band))

        let ms = ModeEquivalence.adifModeSubmode(qso.mode)
        fields.append(field("MODE", ms.mode))
        if let sub = ms.submode {
            fields.append(field("SUBMODE", sub))
        }
        if let freq = qso.frequency {
            fields.append(field(
                "FREQ", String(format: "%.6f", freq)
            ))
        }

        fields.append(field(
            "QSO_DATE", dateFmt.string(from: qso.timestamp)
        ))
        fields.append(field(
            "TIME_ON", timeFmt.string(from: qso.timestamp)
        ))

        if let rst = qso.rstSent, !rst.isEmpty {
            fields.append(field("RST_SENT", rst))
        }
        if let rst = qso.rstReceived, !rst.isEmpty {
            fields.append(field("RST_RCVD", rst))
        }
    }

    private static func appendStationFields(
        to fields: inout [String], qso: QSO
    ) {
        if !qso.myCallsign.isEmpty {
            fields.append(field("STATION_CALLSIGN", qso.myCallsign))
        }
        if let grid = qso.myGrid, !grid.isEmpty {
            fields.append(field("MY_GRIDSQUARE", grid.uppercased()))
        }
        if let grid = qso.theirGrid, !grid.isEmpty {
            fields.append(field("GRIDSQUARE", grid.uppercased()))
        }
    }

    private static func appendActivationFields(
        to fields: inout [String], qso: QSO
    ) {
        if let park = qso.parkReference, !park.isEmpty {
            fields.append(field("MY_SIG", "POTA"))
            fields.append(field("MY_SIG_INFO", park))
        }
        if let park = qso.theirParkReference, !park.isEmpty {
            fields.append(field("SIG", "POTA"))
            fields.append(field("SIG_INFO", park))
        }
        if let sota = qso.sotaRef, !sota.isEmpty {
            fields.append(field("SOTA_REF", sota))
        }
        if let wwff = qso.wwffRef, !wwff.isEmpty {
            fields.append(field("WWFF_REF", wwff))
        }
        if let satName = qso.satName, !satName.isEmpty {
            fields.append(field("SAT_NAME", satName))
        }
        if let propMode = qso.propMode, !propMode.isEmpty {
            fields.append(field("PROP_MODE", propMode))
        }
    }

    private static func appendContactFields(
        to fields: inout [String], qso: QSO
    ) {
        if let notes = qso.notes, !notes.isEmpty {
            fields.append(field("COMMENT", notes))
        }
        if let name = qso.name, !name.isEmpty {
            fields.append(field("NAME", name))
        }
        if let state = qso.state, !state.isEmpty {
            fields.append(field("STATE", state))
        }
        if let country = qso.country, !country.isEmpty {
            fields.append(field("COUNTRY", country))
        }
        if let power = qso.power {
            fields.append(field("TX_PWR", String(power)))
        }
    }
}
