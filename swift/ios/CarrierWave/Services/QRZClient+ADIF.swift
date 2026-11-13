import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - QRZClient ADIF Helpers

extension QRZClient {
    /// Decode ADIF from QRZ response (URL decode then HTML entity decode)
    func decodeADIF(_ encoded: String) -> String {
        var decoded = encoded.removingPercentEncoding ?? encoded

        let htmlEntities: [(String, String)] = [
            ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&#x27;", "'"),
        ]

        for (entity, char) in htmlEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: char)
        }

        return decoded
    }

    /// Parse ADIF string into QRZFetchedQSO records
    func parseADIFRecords(_ adif: String) -> [QRZFetchedQSO] {
        let records =
            adif.lowercased().contains("<eor>")
                ? adif.components(separatedBy: "<eor>").compactMap { $0.isEmpty ? nil : $0 }
                : adif.components(separatedBy: "<EOR>").compactMap { $0.isEmpty ? nil : $0 }

        return records.compactMap { record in
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return parseADIFRecord(record)
        }
    }

    /// Parse a single ADIF record into a QRZFetchedQSO
    private func parseADIFRecord(_ record: String) -> QRZFetchedQSO? {
        let fields = ADIFParser.extractFields(record)

        guard let callsign = fields["call"],
              let band = fields["band"],
              let rawMode = fields["mode"]
        else {
            return nil
        }

        // Prefer ADIF submode over parent mode (e.g., USB/LSB over SSB, PSK31 over PSK)
        let mode = fields["submode"]?.uppercased() ?? rawMode

        let timestamp =
            ADIFParser.parseTimestamp(
                date: fields["qso_date"],
                time: fields["time_on"]
            ) ?? Date()

        var frequency: Double?
        if let freqStr = fields["freq"], let freq = Double(freqStr) {
            frequency = freq
        }

        let qrzStatus = fields["app_qrzlog_status"]
        let qrzConfirmed = qrzStatus?.uppercased() == "C"
        let lotwDate = parseLotwDate(fields["lotw_qsl_rcvd"])

        // DXCC entity number
        let dxcc = fields["dxcc"].flatMap { Int($0) }

        // My park reference: MY_SIG_INFO or MY_POTA_REF (activator's park)
        let myParkRef = fields["my_sig_info"] ?? fields["my_pota_ref"]
        // Their park reference: SIG_INFO (contacted station's park)
        let theirParkRef = fields["sig_info"]

        return QRZFetchedQSO(
            callsign: callsign.uppercased(), band: band.lowercased(), mode: mode.uppercased(),
            frequency: frequency, timestamp: timestamp,
            rstSent: fields["rst_sent"],
            rstReceived: fields["rst_rcvd"],
            myCallsign: fields["station_callsign"],
            myGrid: fields["my_gridsquare"],
            theirGrid: fields["gridsquare"],
            parkReference: myParkRef,
            theirParkReference: theirParkRef,
            notes: fields["comment"],
            qrzLogId: fields["app_qrzlog_logid"],
            qrzConfirmed: qrzConfirmed, lotwConfirmedDate: lotwDate, dxcc: dxcc, rawADIF: record
        )
    }

    /// Parse LoTW date string
    func parseLotwDate(_ dateStr: String?) -> Date? {
        guard let dateStr, !dateStr.isEmpty else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"

        return formatter.date(from: dateStr)
    }

    /// Generate ADIF for a QSO
    func generateADIF(for qso: QSO) -> String {
        var fields: [String] = []

        func addField(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else {
                return
            }
            fields.append("<\(name):\(value.utf8.count)>\(value)")
        }

        addField("call", qso.callsign)
        addField("band", qso.band)
        let modeSubmode = ModeEquivalence.adifModeSubmode(qso.mode)
        addField("mode", modeSubmode.mode)
        if let submode = modeSubmode.submode {
            addField("submode", submode)
        }

        if let freq = qso.frequency {
            addField("freq", String(format: "%.6f", freq))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        addField("qso_date", dateFormatter.string(from: qso.timestamp))

        dateFormatter.dateFormat = "HHmm"
        addField("time_on", dateFormatter.string(from: qso.timestamp))

        addField("rst_sent", qso.rstSent)
        addField("rst_rcvd", qso.rstReceived)
        addField("station_callsign", qso.stationCallsign ?? qso.myCallsign)
        addField("operator", qso.myCallsign)
        addField("my_gridsquare", qso.myGrid)
        addField("gridsquare", qso.theirGrid)
        // My park reference (activator's park)
        if let myPark = qso.parkReference {
            addField("my_sig", "POTA")
            addField("my_sig_info", myPark)
        }
        // Their park reference (contacted station's park)
        if let theirPark = qso.theirParkReference {
            addField("sig", "POTA")
            addField("sig_info", theirPark)
        }
        addField("comment", commentForUpload(qso))
        appendContactADIFFields(addField, qso: qso)

        return fields.joined(separator: " ") + " <eor>"
    }

    /// Contact-info tail of the QRZ upload record, incl. the satellite fields
    /// (QRZ matches on PROP_MODE/SAT_NAME for satellite QSOs).
    private func appendContactADIFFields(_ addField: (String, String?) -> Void, qso: QSO) {
        addField("name", qso.name)
        addField("qth", qso.qth)
        addField("state", qso.state)
        addField("country", qso.country)
        if let dxcc = qso.dxcc {
            addField("dxcc", String(dxcc))
        }
        if let power = qso.power {
            addField("tx_pwr", String(power))
        }
        addField("sat_name", qso.satName)
        addField("prop_mode", qso.propMode)
    }

    /// Resolve the COMMENT value to upload to QRZ. CAR-243: only emit when the
    /// notes were authored by the user in Carrier Wave — never push notes that
    /// arrived via sync/import/round-trip. Park references stay in the proper
    /// `sig_info` field and are stripped from the freeform comment.
    private func commentForUpload(_ qso: QSO) -> String? {
        guard qso.notesUserAuthored else {
            return nil
        }
        return qso.notes.flatMap { ParkReference.stripFromFreeText($0) } ?? qso.notes
    }

    /// Form-encode a dictionary for POST body
    /// Uses %20 for spaces instead of + because QRZ's API does not decode + as spaces
    nonisolated func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")

        return params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}
