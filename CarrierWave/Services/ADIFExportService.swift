// ADIF Export Service
//
// Generates comprehensive ADIF files for activations in the background.
// Includes all QSO fields in valid ADIF 3.1.5 format.

import CarrierWaveCore
import Foundation

// MARK: - QSOExportSnapshot

/// Sendable snapshot of QSO data for background ADIF generation
struct QSOExportSnapshot: Sendable {
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
        sotaRef = qso.sotaRef
        dxcc = qso.dxcc
        qrzConfirmed = qso.qrzConfirmed
        lotwConfirmed = qso.lotwConfirmed
        lotwConfirmedDate = qso.lotwConfirmedDate
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
    let theirParkReference: String?
    let notes: String?
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let power: Int?
    let sotaRef: String?
    let dxcc: Int?
    let qrzConfirmed: Bool
    let lotwConfirmed: Bool
    let lotwConfirmedDate: Date?
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
        lines.append(formatField("ADIF_VER", "3.1.5"))

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
        appendConfirmationFields(to: &fields, snapshot: snapshot)

        if let notes = snapshot.notes, !notes.isEmpty {
            fields.append(formatField("COMMENT", notes))
        }

        return fields.joined() + "<EOR>"
    }

    private func appendCoreFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
        fields.append(formatField("CALL", snapshot.callsign))
        fields.append(formatField("BAND", snapshot.band))
        fields.append(formatField("MODE", snapshot.mode))

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

    private func appendStationFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
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

    private func appendContactFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
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

    private func appendConfirmationFields(to fields: inout [String], snapshot: QSOExportSnapshot) {
        if snapshot.qrzConfirmed {
            fields.append(formatField("QRZ_QSO_UPLOAD_STATUS", "Y"))
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

    // MARK: - Field Formatting

    /// Format a single ADIF field: <NAME:length>value
    private func formatField(_ name: String, _ value: String) -> String {
        "<\(name.uppercased()):\(value.count)>\(value)"
    }
}

// MARK: - ADIFExportResult

struct ADIFExportResult: Sendable {
    let content: String
    let filename: String
    let qsoCount: Int
}
