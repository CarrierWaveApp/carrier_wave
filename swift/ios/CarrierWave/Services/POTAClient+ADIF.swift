import CarrierWaveData
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
        lines.append(formatField("ADIF_VER", "3.1.7"))
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
        let modeSubmode = Self.potaADIFMode(for: qso.mode)
        fields.append(formatField("MODE", modeSubmode.mode))
        if let submode = modeSubmode.submode {
            fields.append(formatField("SUBMODE", submode))
        }
        fields.append(formatField("BAND", qso.band))

        if let freq = qso.frequency {
            fields.append(formatField("FREQ", String(format: "%.6f", freq)))
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

        // Station info — use QSO's stationCallsign (club call) or myCallsign (operator),
        // falling back to the activator callsign (for HAMRS imports lacking STATION_CALLSIGN)
        let effectiveStation = qso.stationCallsign
            ?? (qso.myCallsign.isEmpty ? activatorCallsign : qso.myCallsign)
        if let effectiveStation, !effectiveStation.isEmpty {
            fields.append(formatField("STATION_CALLSIGN", effectiveStation))
        }
        let operatorCall = qso.myCallsign.isEmpty ? activatorCallsign : qso.myCallsign
        if let operatorCall, !operatorCall.isEmpty {
            fields.append(formatField("OPERATOR", operatorCall))
        }

        // Grid squares
        if let theirGrid = qso.theirGrid, !theirGrid.isEmpty {
            fields.append(formatField("GRIDSQUARE", theirGrid))
        }
        if let myGrid = qso.myGrid, !myGrid.isEmpty {
            fields.append(formatField("MY_GRIDSQUARE", myGrid))
        }

        appendPOTAFields(to: &fields, qso: qso, parkReference: parkReference)

        // Satellite fields
        if let satName = qso.satName, !satName.isEmpty {
            fields.append(formatField("SAT_NAME", satName))
        }
        if let propMode = qso.propMode, !propMode.isEmpty {
            fields.append(formatField("PROP_MODE", propMode))
        }

        // Comment — strip park references since they're in the proper SIG_INFO fields
        if let notes = qso.notes, !notes.isEmpty {
            let cleaned = ParkReference.stripFromFreeText(notes) ?? notes
            fields.append(formatField("COMMENT", cleaned))
        }

        return fields.joined() + "<EOR>"
    }

    private func appendPOTAFields(to fields: inout [String], qso: QSO, parkReference: String) {
        fields.append(formatField("MY_SIG", "POTA"))
        fields.append(formatField("MY_SIG_INFO", parkReference))
        fields.append(formatField("MY_POTA_REF", parkReference))

        if let theirPark = qso.theirParkReference, !theirPark.isEmpty {
            fields.append(formatField("SIG", "POTA"))
            fields.append(formatField("SIG_INFO", theirPark))
            fields.append(formatField("POTA_REF", theirPark))
        }

        var qslMsg = "POTA \(parkReference)"
        if let theirPark = qso.theirParkReference, !theirPark.isEmpty {
            qslMsg += " P2P \(theirPark)"
        }
        fields.append(formatField("QSLMSG", qslMsg))
    }

    /// Format a single ADIF field: <NAME:length>value
    func formatField(_ name: String, _ value: String) -> String {
        "<\(name.uppercased()):\(value.utf8.count)>\(value)"
    }

    /// POTA-specific ADIF mode mapping. POTA validates against the ADIF 3.x
    /// mode enumeration and rejects `PHONE` / `DATA` outright. Delegates to
    /// the shared normalizer in CarrierWaveCore so validation tests can run
    /// locally without the app target.
    static func potaADIFMode(for mode: String) -> (mode: String, submode: String?) {
        ModeEquivalence.normalizeForStrictADIF(mode)
    }
}
