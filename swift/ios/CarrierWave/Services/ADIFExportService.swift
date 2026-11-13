// ADIF Export Service
//
// Generates comprehensive ADIF files for activations in the background.
// Includes all QSO fields in valid ADIF 3.1.7 format.

import CarrierWaveData
import Foundation

// MARK: - QSOExportSnapshot

/// Sendable snapshot of QSO data for background ADIF generation
struct QSOExportSnapshot {
    // MARK: Lifecycle

    /// Create a snapshot from a QSO (must be called on MainActor)
    @MainActor
    init(from qso: QSO) {
        callsign = qso.callsign
        band = qso.band
        mode = qso.mode
        frequency = qso.frequency
        timestamp = qso.timestamp
        rstSent = qso.rstSent
        rstReceived = qso.rstReceived
        myCallsign = qso.myCallsign
        myGrid = qso.myGrid
        theirGrid = qso.theirGrid
        theirParkReference = qso.theirParkReference
        notes = qso.notes
        name = qso.name
        qth = qso.qth
        state = qso.state
        country = qso.country
        power = qso.power
        myRig = qso.myRig
        sotaRef = qso.sotaRef
        dxcc = qso.dxcc
        qrzConfirmed = qso.qrzConfirmed
        lotwConfirmed = qso.lotwConfirmed
        lotwConfirmedDate = qso.lotwConfirmedDate
        stationCallsign = qso.stationCallsign
        parkReference = qso.parkReference
        contestName = qso.contestName
        contestSerialSent = qso.contestSerialSent
        contestSerialReceived = qso.contestSerialReceived
        contestExchangeSent = qso.contestExchangeSent
        contestExchangeReceived = qso.contestExchangeReceived
        satName = qso.satName
        propMode = qso.propMode
    }

    // MARK: Internal

    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    var myCallsign: String
    let myGrid: String?
    let theirGrid: String?
    let theirParkReference: String?
    let notes: String?
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let power: Int?
    let myRig: String?
    let sotaRef: String?
    let dxcc: Int?
    let qrzConfirmed: Bool
    let lotwConfirmed: Bool
    let lotwConfirmedDate: Date?
    var stationCallsign: String?
    let parkReference: String?
    let contestName: String?
    let contestSerialSent: Int?
    let contestSerialReceived: Int?
    let contestExchangeSent: String?
    let contestExchangeReceived: String?
    let satName: String?
    let propMode: String?
}

// MARK: - ADIFExportService

actor ADIFExportService {
    // MARK: Internal

    /// Generate ADIF content for an activation's QSOs
    /// Runs on background actor to avoid blocking UI
    func generateADIF(
        for snapshots: [QSOExportSnapshot],
        parkReference: String,
        parkName: String?,
        activatorCallsign: String
    ) async -> String {
        var lines: [String] = []

        // Header
        lines.append(
            contentsOf: buildHeader(
                snapshots: snapshots,
                parkReference: parkReference,
                parkName: parkName,
                activatorCallsign: activatorCallsign
            )
        )
        lines.append("<EOH>")
        lines.append("")

        // QSO Records
        for snapshot in snapshots.sorted(by: { $0.timestamp < $1.timestamp }) {
            lines.append(buildQSORecord(snapshot, parkReference: parkReference))
            lines.append("")
            // Yield periodically for large exports
            await Task.yield()
        }

        return lines.joined(separator: "\n")
    }

    /// Generate combined ADIF content for multiple activations
    func generateBulkADIF(for activations: [BulkADIFActivation]) async -> String {
        var lines: [String] = []

        // Header
        let parkList = activations.map(\.parkReference).joined(separator: ", ")
        lines.append("ADIF export for \(activations.count) activations: \(parkList)")
        lines.append("")
        lines.append(formatField("ADIF_VER", "3.1.7"))
        lines.append(formatField("PROGRAMID", "CarrierWave"))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        lines.append(formatField("PROGRAMVERSION", version))
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMdd HHmmss"
        timestampFormatter.timeZone = TimeZone(identifier: "UTC")
        lines.append(formatField("CREATED_TIMESTAMP", timestampFormatter.string(from: Date())))
        lines.append("<EOH>")
        lines.append("")

        // QSO records grouped by activation
        for activation in activations {
            lines.append("// Activation: \(activation.parkReference)")
            if let name = activation.parkName {
                lines.append("// Park: \(name)")
            }
            lines.append("")

            for snapshot in activation.snapshots.sorted(by: { $0.timestamp < $1.timestamp }) {
                lines.append(buildQSORecord(snapshot, parkReference: activation.parkReference))
                lines.append("")
                await Task.yield()
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Generate a filename for a bulk ADIF export
    func generateBulkFilename(activationCount: Int, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = dateFormatter.string(from: date)
        return "pota_bulk_\(activationCount)_activations_\(dateStr).adi"
    }

    /// Generate a filename for the ADIF export
    func generateFilename(
        parkReference: String,
        activatorCallsign: String,
        date: Date
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = dateFormatter.string(from: date)

        // Sanitize callsign and park reference for filename
        let safeCallsign =
            activatorCallsign
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: " ", with: "_")
        let safePark =
            parkReference
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: " ", with: "_")

        return "\(safeCallsign)_\(safePark)_\(dateStr).adi"
    }

    // MARK: - Multi-Operator Export

    /// Generate per-operator ADIF files for a multi-op session.
    /// Each file is a complete copy of all QSOs with STATION_CALLSIGN and OPERATOR
    /// overridden to the given operator's callsign.
    func generateMultiOpADIF(
        for config: MultiOpExportConfig
    ) async -> [MultiOpExportFile] {
        var files: [MultiOpExportFile] = []
        for callsign in config.operatorCallsigns {
            let overridden = config.snapshots.map { snapshot in
                var copy = snapshot
                copy.myCallsign = callsign
                copy.stationCallsign = callsign
                return copy
            }
            let content = await generateADIF(
                for: overridden,
                parkReference: config.parkReference ?? "",
                parkName: config.parkName,
                activatorCallsign: callsign
            )
            let title = config.sessionTitle ?? formatDate(config.sessionDate)
            let sanitized = title.replacingOccurrences(
                of: "[^a-zA-Z0-9_-]", with: "_",
                options: .regularExpression
            )
            let filename = "\(sanitized)-\(callsign).adi"
            files.append(MultiOpExportFile(
                callsign: callsign, content: content,
                filename: filename, qsoCount: config.snapshots.count
            ))
        }
        return files
    }

    func appendCoreFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
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

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd"
        fields.append(formatField("QSO_DATE", dateFormatter.string(from: snapshot.timestamp)))
        dateFormatter.dateFormat = "HHmmss"
        fields.append(formatField("TIME_ON", dateFormatter.string(from: snapshot.timestamp)))

        if let rstRcvd = snapshot.rstReceived, !rstRcvd.isEmpty {
            fields.append(formatField("RST_RCVD", rstRcvd))
        }
        if let rstSent = snapshot.rstSent, !rstSent.isEmpty {
            fields.append(formatField("RST_SENT", rstSent))
        }
    }

    func appendStationFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
        let stationCall = snapshot.stationCallsign ?? snapshot.myCallsign
        if !stationCall.isEmpty {
            fields.append(formatField("STATION_CALLSIGN", stationCall))
        }
        if !snapshot.myCallsign.isEmpty {
            fields.append(formatField("OPERATOR", snapshot.myCallsign))
        }
        if let theirGrid = snapshot.theirGrid, !theirGrid.isEmpty {
            fields.append(formatField("GRIDSQUARE", theirGrid.uppercased()))
        }
        if let myGrid = snapshot.myGrid, !myGrid.isEmpty {
            fields.append(formatField("MY_GRIDSQUARE", myGrid.uppercased()))
        }
    }

    func appendContactFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
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
        if let myRig = snapshot.myRig {
            fields.append(formatField("MY_RIG", myRig))
        }
    }

    func appendConfirmationFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
        if snapshot.qrzConfirmed {
            fields.append(formatField("QRZCOM_QSO_UPLOAD_STATUS", "Y"))
        }
        if snapshot.lotwConfirmed {
            fields.append(formatField("LOTW_QSL_RCVD", "Y"))
            if let lotwDate = snapshot.lotwConfirmedDate {
                let dateFormatter = DateFormatter()
                dateFormatter.timeZone = TimeZone(identifier: "UTC")
                dateFormatter.dateFormat = "yyyyMMdd"
                fields.append(formatField("LOTW_QSLRDATE", dateFormatter.string(from: lotwDate)))
            }
        }
    }

    /// Satellite fields — LoTW requires both SAT_NAME and PROP_MODE for
    /// satellite credit (TQSL consumes this export).
    func appendSatelliteFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
        if let satName = snapshot.satName, !satName.isEmpty {
            fields.append(formatField("SAT_NAME", satName))
        }
        if let propMode = snapshot.propMode, !propMode.isEmpty {
            fields.append(formatField("PROP_MODE", propMode))
        }
    }

    func appendContestFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
        if let contestId = snapshot.contestName, !contestId.isEmpty {
            fields.append(formatField("CONTEST_ID", contestId))
        }
        if let stx = snapshot.contestSerialSent {
            fields.append(formatField("STX", String(stx)))
        }
        if let srx = snapshot.contestSerialReceived {
            fields.append(formatField("SRX", String(srx)))
        }
        if let stxStr = snapshot.contestExchangeSent, !stxStr.isEmpty {
            fields.append(formatField("STX_STRING", stxStr))
        }
        if let srxStr = snapshot.contestExchangeReceived, !srxStr.isEmpty {
            fields.append(formatField("SRX_STRING", srxStr))
        }
    }

    // MARK: - Field Formatting

    /// Format a single ADIF field: <NAME:length>value
    func formatField(_ name: String, _ value: String) -> String {
        "<\(name.uppercased()):\(value.utf8.count)>\(value)"
    }

    // MARK: Private

    // MARK: - Header Generation

    private func buildHeader(
        snapshots: [QSOExportSnapshot],
        parkReference: String,
        parkName: String?,
        activatorCallsign: String
    ) -> [String] {
        var lines: [String] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = snapshots.first.map { dateFormatter.string(from: $0.timestamp) } ?? "unknown"

        // Header comment
        var headerComment = "ADIF export for \(activatorCallsign): POTA \(parkReference)"
        if let name = parkName {
            headerComment += " (\(name))"
        }
        headerComment += " on \(dateStr)"
        lines.append(headerComment)
        lines.append("")

        // ADIF version
        lines.append(formatField("ADIF_VER", "3.1.7"))

        // Program info
        lines.append(formatField("PROGRAMID", "CarrierWave"))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        lines.append(formatField("PROGRAMVERSION", version))

        // Creation timestamp
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMdd HHmmss"
        timestampFormatter.timeZone = TimeZone(identifier: "UTC")
        lines.append(formatField("CREATED_TIMESTAMP", timestampFormatter.string(from: Date())))

        return lines
    }

    // MARK: - QSO Record Generation

    private func buildQSORecord(_ snapshot: QSOExportSnapshot, parkReference: String) -> String {
        var fields: [String] = []

        appendCoreFields(to: &fields, snapshot: snapshot)
        appendStationFields(to: &fields, snapshot: snapshot)
        appendContactFields(to: &fields, snapshot: snapshot)
        appendPOTAFields(to: &fields, snapshot: snapshot, parkReference: parkReference)
        appendSatelliteFields(to: &fields, snapshot: snapshot)
        appendConfirmationFields(to: &fields, snapshot: snapshot)
        appendContestFields(to: &fields, snapshot: snapshot)

        // Strip park references from COMMENT — they're in the proper SIG_INFO fields
        if let notes = snapshot.notes, !notes.isEmpty {
            let cleaned = ParkReference.stripFromFreeText(notes) ?? notes
            fields.append(formatField("COMMENT", cleaned))
        }

        return fields.joined() + "<EOR>"
    }

    private func appendPOTAFields(
        to fields: inout [String],
        snapshot: QSOExportSnapshot,
        parkReference: String
    ) {
        fields.append(formatField("MY_SIG", "POTA"))
        fields.append(formatField("MY_SIG_INFO", parkReference))
        fields.append(formatField("MY_POTA_REF", parkReference))

        if let theirPark = snapshot.theirParkReference, !theirPark.isEmpty {
            fields.append(formatField("SIG", "POTA"))
            fields.append(formatField("SIG_INFO", theirPark))
            fields.append(formatField("POTA_REF", theirPark))
        }
        if let sotaRef = snapshot.sotaRef, !sotaRef.isEmpty {
            fields.append(formatField("SOTA_REF", sotaRef))
        }

        var qslMsg = "POTA \(parkReference)"
        if let theirPark = snapshot.theirParkReference, !theirPark.isEmpty {
            qslMsg += " P2P \(theirPark)"
        }
        fields.append(formatField("QSLMSG", qslMsg))
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - ADIFExportResult

struct ADIFExportResult {
    let content: String
    let filename: String
    let qsoCount: Int
}

// MARK: - BulkADIFActivation

/// Data for a single activation in a bulk ADIF export
struct BulkADIFActivation {
    let snapshots: [QSOExportSnapshot]
    let parkReference: String
    let parkName: String?
}

// MARK: - MultiOpExportConfig

/// Configuration for multi-operator ADIF export
struct MultiOpExportConfig {
    let snapshots: [QSOExportSnapshot]
    let operatorCallsigns: [String]
    let parkReference: String?
    let parkName: String?
    let sessionTitle: String?
    let sessionDate: Date
}

// MARK: - MultiOpExportFile

/// A single operator's ADIF export file from a multi-op session
struct MultiOpExportFile {
    let callsign: String
    let content: String
    let filename: String
    let qsoCount: Int
}
