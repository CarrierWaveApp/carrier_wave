import Foundation

// MARK: - POTAClient ADIF Generation

extension POTAClient {
    func generateADIF(for qsos: [QSO], parkReference: String, activatorCallsign: String? = nil)
        -> String
    {
        var lines: [String] = []

        // Header
        lines.append(contentsOf: buildADIFHeader(qsos: qsos, parkReference: parkReference))
        lines.append("<EOH>")
        lines.append("")

        // QSO Records
        for qso in qsos {
            lines.append(
                buildQSORecord(
                    qso, parkReference: parkReference, activatorCallsign: activatorCallsign
                )
            )
        }

        return lines.joined(separator: "\n")
    }

    private func buildADIFHeader(qsos: [QSO], parkReference: String) -> [String] {
        var lines: [String] = []

        let activator = qsos.first?.myCallsign ?? "UNKNOWN"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = qsos.first.map { dateFormatter.string(from: $0.timestamp) } ?? "unknown"

        lines.append("ADIF for \(activator): POTA \(parkReference) on \(dateStr)")
        lines.append(formatField("ADIF_VER", "3.1.5"))
        lines.append(formatField("PROGRAMID", "CarrierWave"))

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        lines.append(formatField("PROGRAMVERSION", version))

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMdd HHmmss"
        timestampFormatter.timeZone = TimeZone(identifier: "UTC")
        lines.append(formatField("CREATED_TIMESTAMP", timestampFormatter.string(from: Date())))

        return lines
    }

    private func buildQSORecord(_ qso: QSO, parkReference: String, activatorCallsign: String? = nil)
        -> String
    {
        var fields: [String] = []

        // Core QSO fields
        fields.append(formatField("CALL", qso.callsign))
        fields.append(formatField("MODE", qso.mode))
        fields.append(formatField("BAND", qso.band))

        if let freq = qso.frequency {
            fields.append(formatField("FREQ", String(format: "%.4f", freq)))
        }

        let qsoDateFormatter = DateFormatter()
        qsoDateFormatter.timeZone = TimeZone(identifier: "UTC")
        qsoDateFormatter.dateFormat = "yyyyMMdd"
        fields.append(formatField("QSO_DATE", qsoDateFormatter.string(from: qso.timestamp)))

        qsoDateFormatter.dateFormat = "HHmmss"
        fields.append(formatField("TIME_ON", qsoDateFormatter.string(from: qso.timestamp)))

        // Signal reports
        if let rstRcvd = qso.rstReceived, !rstRcvd.isEmpty {
            fields.append(formatField("RST_RCVD", rstRcvd))
        }
        if let rstSent = qso.rstSent, !rstSent.isEmpty {
            fields.append(formatField("RST_SENT", rstSent))
        }

        // Station info — use QSO's myCallsign, falling back to the activator callsign
        // (needed for HAMRS imports that may lack STATION_CALLSIGN in their ADIF)
        let stationCallsign = qso.myCallsign.isEmpty ? activatorCallsign : qso.myCallsign
        if let stationCallsign, !stationCallsign.isEmpty {
            fields.append(formatField("STATION_CALLSIGN", stationCallsign))
            fields.append(formatField("OPERATOR", stationCallsign))
        }

        // Grid squares
        if let theirGrid = qso.theirGrid, !theirGrid.isEmpty {
            fields.append(formatField("GRIDSQUARE", theirGrid))
        }
        if let myGrid = qso.myGrid, !myGrid.isEmpty {
            fields.append(formatField("MY_GRIDSQUARE", myGrid))
        }

        // POTA fields
        fields.append(formatField("QSLMSG", "POTA \(parkReference)"))
        fields.append(formatField("MY_SIG", "POTA"))
        fields.append(formatField("MY_SIG_INFO", parkReference))
        fields.append(formatField("MY_POTA_REF", parkReference))

        // Comment
        if let notes = qso.notes, !notes.isEmpty {
            fields.append(formatField("COMMENT", notes))
        }

        return fields.joined() + "<EOR>"
    }

    /// Format a single ADIF field: <NAME:length>value
    func formatField(_ name: String, _ value: String) -> String {
        "<\(name.uppercased()):\(value.count)>\(value)"
    }
}
