import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - ADIF Parsing

extension EQSLClient {
    /// Parse ADIF response from eQSL into fetched QSO records
    func parseADIFRecords(_ adif: String) -> [EQSLFetchedQSO] {
        // Skip header
        let headerEnd: String.Index =
            if let range = adif.range(of: "<EOH>", options: .caseInsensitive) {
                range.upperBound
            } else {
                adif.startIndex
            }

        let body = String(adif[headerEnd...])

        let parts = splitOnEOR(body)
        var result: [EQSLFetchedQSO] = []

        for record in parts {
            let trimmed = record.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty else {
                continue
            }
            if let qso = parseADIFRecord(trimmed) {
                result.append(qso)
            }
        }

        return result
    }

    /// Split ADIF body on <EOR> tags (case insensitive)
    private func splitOnEOR(_ body: String) -> [String] {
        let pattern = "<[Ee][Oo][Rr]>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return body.components(separatedBy: "<EOR>")
        }

        let nsBody = body as NSString
        let matches = regex.matches(
            in: body, range: NSRange(location: 0, length: nsBody.length)
        )

        var parts: [String] = []
        var lastEnd = 0

        for match in matches {
            let part = nsBody.substring(
                with: NSRange(location: lastEnd,
                              length: match.range.location - lastEnd)
            )
            parts.append(part)
            lastEnd = match.range.location + match.range.length
        }

        return parts
    }

    func parseADIFRecord(_ record: String) -> EQSLFetchedQSO? {
        let fields = ADIFParser.extractFields(record)

        guard let callsign = fields["call"],
              let band = fields["band"],
              let rawMode = fields["mode"]
        else {
            return nil
        }

        // Prefer ADIF submode over parent mode (e.g., USB/LSB over SSB)
        let mode = fields["submode"]?.uppercased() ?? rawMode

        let timestamp = ADIFParser.parseTimestamp(
            date: fields["qso_date"],
            time: fields["time_on"]
        ) ?? Date()

        var frequency: Double?
        if let freqStr = fields["freq"] {
            frequency = Double(freqStr)
        }

        // eQSL inbox entries are confirmed by definition
        let qslDate = parseQSLDate(fields["qslrdate"])

        return EQSLFetchedQSO(
            callsign: callsign.uppercased(),
            band: band.lowercased(),
            mode: mode.uppercased(),
            frequency: frequency,
            timestamp: timestamp,
            // eQSL InBox records are from the OTHER station's perspective:
            // their RST_SENT = what they sent us = our RST_RCVD
            // their RST_RCVD = what they received from us = our RST_SENT
            rstSent: fields["rst_rcvd"],
            rstReceived: fields["rst_sent"],
            myCallsign: fields["station_callsign"],
            myGrid: fields["my_gridsquare"],
            theirGrid: fields["gridsquare"],
            qslReceived: true,
            qslReceivedDate: qslDate ?? timestamp,
            rawADIF: record
        )
    }

    private func parseQSLDate(_ dateStr: String?) -> Date? {
        guard let dateStr else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: dateStr)
    }
}

// MARK: - ADIF Generation

extension EQSLClient {
    /// Build ADIF string for uploading QSOs
    func buildADIFForUpload(_ qsos: [QSO]) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        var lines = [
            "Carrier Wave eQSL Upload",
            "<ADIF_VER:5>3.1.7",
            "<PROGRAMID:11>CarrierWave",
            "<PROGRAMVERSION:\(version.utf8.count)>\(version)",
            "<EOH>",
        ]

        for qso in qsos {
            lines.append(generateADIF(for: qso))
        }

        return lines.joined(separator: "\n")
    }

    func generateADIF(for qso: QSO) -> String {
        var fields: [String] = []

        func addField(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else {
                return
            }
            fields.append("<\(name):\(value.utf8.count)>\(value)")
        }

        addField("CALL", qso.callsign)
        addField("BAND", qso.band)
        let modeSubmode = ModeEquivalence.adifModeSubmode(qso.mode)
        addField("MODE", modeSubmode.mode)
        if let submode = modeSubmode.submode {
            addField("SUBMODE", submode)
        }

        if let freq = qso.frequency {
            addField("FREQ", String(format: "%.4f", freq))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        addField("QSO_DATE", dateFormatter.string(from: qso.timestamp))

        dateFormatter.dateFormat = "HHmm"
        addField("TIME_ON", dateFormatter.string(from: qso.timestamp))

        addField("RST_SENT", qso.rstSent)
        addField("RST_RCVD", qso.rstReceived)
        addField("STATION_CALLSIGN", qso.stationCallsign ?? qso.myCallsign)
        addField("OPERATOR", qso.myCallsign)
        addField("MY_GRIDSQUARE", qso.myGrid)
        addField("GRIDSQUARE", qso.theirGrid)
        addField("SAT_NAME", qso.satName)
        addField("PROP_MODE", qso.propMode)

        return fields.joined(separator: " ") + " <EOR>"
    }
}

// MARK: - Upload Response Parsing

extension EQSLClient {
    /// Parse eQSL upload response to extract counts
    func parseUploadResponse(
        _ response: String, totalQSOs: Int
    ) -> EQSLUploadResult {
        let lowered = response.lowercased()

        // eQSL returns "Result: N of M records added"
        // and may include "N duplicates" or "N errors"
        var uploaded = 0
        var duplicates = 0

        if let range = lowered.range(of: #"(\d+) of \d+ records? added"#,
                                     options: .regularExpression)
        {
            let match = String(lowered[range])
            let digits = match.prefix(while: \.isNumber)
            uploaded = Int(digits) ?? 0
        }

        if let range = lowered.range(of: #"(\d+) duplicate"#,
                                     options: .regularExpression)
        {
            let match = String(lowered[range])
            let digits = match.prefix(while: \.isNumber)
            duplicates = Int(digits) ?? 0
        }

        // If no pattern matched but no error, assume all uploaded
        if uploaded == 0, duplicates == 0, !lowered.contains("error") {
            uploaded = totalQSOs
        }

        let rejected = totalQSOs - uploaded - duplicates
        return EQSLUploadResult(
            uploaded: uploaded,
            rejected: max(0, rejected),
            duplicates: duplicates
        )
    }
}

// MARK: - Network Helpers

extension EQSLClient {
    func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? string
    }

    func appendFormField(
        _ data: inout Data, boundary: String,
        name: String, value: String
    ) {
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data(
            "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8
        ))
        data.append(Data("\(value)\r\n".utf8))
    }

    func appendFileField(
        _ data: inout Data, boundary: String,
        name: String, filename: String, content: String
    ) {
        data.append(Data("--\(boundary)\r\n".utf8))
        let disposition = "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        data.append(Data(disposition.utf8))
        data.append(Data(
            "Content-Type: application/octet-stream\r\n\r\n".utf8
        ))
        data.append(Data(content.utf8))
        data.append(Data("\r\n".utf8))
    }
}
