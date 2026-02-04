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
        let fields = parseADIFFields(record)

        guard let callsign = fields["CALL"] ?? fields["call"],
              let band = fields["BAND"] ?? fields["band"],
              let mode = fields["MODE"] ?? fields["mode"]
        else {
            return nil
        }

        let timestamp =
            parseTimestamp(
                date: fields["QSO_DATE"] ?? fields["qso_date"],
                time: fields["TIME_ON"] ?? fields["time_on"]
            ) ?? Date()

        var frequency: Double?
        if let freqStr = fields["FREQ"] ?? fields["freq"], let freq = Double(freqStr) {
            frequency = freq
        }

        let qrzStatus = fields["APP_QRZLOG_STATUS"] ?? fields["app_qrzlog_status"]
        let qrzConfirmed = qrzStatus?.uppercased() == "C"
        let lotwDate = parseLotwDate(fields["LOTW_QSL_RCVD"] ?? fields["lotw_qsl_rcvd"])

        // DXCC entity number
        let dxcc = (fields["DXCC"] ?? fields["dxcc"]).flatMap { Int($0) }

        // My park reference: MY_SIG_INFO or MY_POTA_REF (activator's park)
        let myParkRef =
            fields["MY_SIG_INFO"] ?? fields["my_sig_info"]
                ?? fields["MY_POTA_REF"] ?? fields["my_pota_ref"]
        // Their park reference: SIG_INFO (contacted station's park)
        let theirParkRef = fields["SIG_INFO"] ?? fields["sig_info"]

        return QRZFetchedQSO(
            callsign: callsign.uppercased(), band: band.uppercased(), mode: mode.uppercased(),
            frequency: frequency, timestamp: timestamp,
            rstSent: fields["RST_SENT"] ?? fields["rst_sent"],
            rstReceived: fields["RST_RCVD"] ?? fields["rst_rcvd"],
            myCallsign: fields["STATION_CALLSIGN"] ?? fields["station_callsign"],
            myGrid: fields["MY_GRIDSQUARE"] ?? fields["my_gridsquare"],
            theirGrid: fields["GRIDSQUARE"] ?? fields["gridsquare"],
            parkReference: myParkRef,
            theirParkReference: theirParkRef,
            notes: fields["COMMENT"] ?? fields["comment"],
            qrzLogId: fields["APP_QRZLOG_LOGID"] ?? fields["app_qrzlog_logid"],
            qrzConfirmed: qrzConfirmed, lotwConfirmedDate: lotwDate, dxcc: dxcc, rawADIF: record
        )
    }

    /// Parse ADIF fields from a record string
    func parseADIFFields(_ record: String) -> [String: String] {
        var fields: [String: String] = [:]

        let pattern = #"<(\w+):(\d+)(?::\w+)?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return fields
        }

        let nsRecord = record as NSString
        let matches = regex.matches(
            in: record, options: [], range: NSRange(location: 0, length: nsRecord.length)
        )

        for match in matches {
            guard match.numberOfRanges >= 3 else {
                continue
            }

            let fieldNameRange = match.range(at: 1)
            let lengthRange = match.range(at: 2)

            let fieldName = nsRecord.substring(with: fieldNameRange)
            guard let length = Int(nsRecord.substring(with: lengthRange)) else {
                continue
            }

            let valueStart = match.range.location + match.range.length
            if valueStart + length <= nsRecord.length {
                let valueRange = NSRange(location: valueStart, length: length)
                fields[fieldName] = nsRecord.substring(with: valueRange)
            }
        }

        return fields
    }

    /// Parse ADIF date/time fields into Date
    func parseTimestamp(date: String?, time: String?) -> Date? {
        guard let date else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")

        if let time, time.count >= 4 {
            formatter.dateFormat = "yyyyMMddHHmm"
            return formatter.date(from: date + time.prefix(4))
        } else {
            formatter.dateFormat = "yyyyMMdd"
            return formatter.date(from: date)
        }
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
            fields.append("<\(name):\(value.count)>\(value)")
        }

        addField("call", qso.callsign)
        addField("band", qso.band)
        addField("mode", qso.mode)

        if let freq = qso.frequency {
            addField("freq", String(format: "%.4f", freq))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        addField("qso_date", dateFormatter.string(from: qso.timestamp))

        dateFormatter.dateFormat = "HHmm"
        addField("time_on", dateFormatter.string(from: qso.timestamp))

        addField("rst_sent", qso.rstSent)
        addField("rst_rcvd", qso.rstReceived)
        addField("station_callsign", qso.myCallsign)
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
        addField("comment", qso.notes)

        return fields.joined(separator: " ") + " <eor>"
    }

    /// Form-encode a dictionary for POST body
    func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")

        return params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let escapedValue =
                value
                    .replacingOccurrences(of: " ", with: "+")
                    .addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}
