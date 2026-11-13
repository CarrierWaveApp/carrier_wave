import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - ADIF Parsing & Generation

extension ClubLogClient {
    /// Parse ADIF string into ClubLogFetchedQSO records
    func parseADIFRecords(_ adif: String) -> [ClubLogFetchedQSO] {
        // Skip header (everything before first <EOH> or <eoh>)
        let headerEnd: String.Index =
            if let eohRange = adif.range(of: "<EOH>", options: .caseInsensitive) {
                eohRange.upperBound
            } else {
                adif.startIndex
            }

        let body = String(adif[headerEnd...])

        // Split on <EOR> or <eor>
        let records = body.components(separatedBy: "<eor>")
            + body.components(separatedBy: "<EOR>")

        // Deduplicate by using a set to track positions
        var seen = Set<String>()
        var result: [ClubLogFetchedQSO] = []

        for record in records {
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)

            if let qso = parseADIFRecord(trimmed) {
                result.append(qso)
            }
        }

        return result
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

        dateFormatter.dateFormat = "HHmmss"
        addField("TIME_ON", dateFormatter.string(from: qso.timestamp))

        addField("RST_SENT", qso.rstSent)
        addField("RST_RCVD", qso.rstReceived)
        addField("STATION_CALLSIGN", qso.stationCallsign ?? qso.myCallsign)
        addField("OPERATOR", qso.myCallsign)
        addField("MY_GRIDSQUARE", qso.myGrid)
        addField("GRIDSQUARE", qso.theirGrid)

        if let myPark = qso.parkReference {
            addField("MY_SIG", "POTA")
            addField("MY_SIG_INFO", myPark)
        }
        if let theirPark = qso.theirParkReference {
            addField("SIG", "POTA")
            addField("SIG_INFO", theirPark)
        }
        addField("SAT_NAME", qso.satName)
        addField("PROP_MODE", qso.propMode)

        // Strip park references from COMMENT — they're in the proper SIG_INFO fields
        let cleanedNotes = qso.notes.flatMap { ParkReference.stripFromFreeText($0) } ?? qso.notes
        addField("COMMENT", cleanedNotes)

        return fields.joined(separator: " ") + " <EOR>"
    }

    /// Filter QSOs to only those matching the account callsign
    func filterQSOsForUpload(
        _ qsos: [QSO], accountCallsign: String
    ) -> (matching: [QSO], skippedCount: Int) {
        var matching: [QSO] = []
        var skipped = 0

        for qso in qsos {
            let qsoCallsign = qso.myCallsign.uppercased()
            if qsoCallsign.isEmpty || qsoCallsign == accountCallsign {
                matching.append(qso)
            } else {
                skipped += 1
            }
        }

        return (matching, skipped)
    }
}

// MARK: - ADIF Record Parsing

extension ClubLogClient {
    /// Parse a single ADIF record into a ClubLogFetchedQSO
    func parseADIFRecord(_ record: String) -> ClubLogFetchedQSO? {
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
        if let freqStr = fields["freq"], let freq = Double(freqStr) {
            frequency = freq
        }

        let dxcc = fields["dxcc"].flatMap { Int($0) }

        let myParkRef = fields["my_sig_info"] ?? fields["my_pota_ref"]
        let theirParkRef = fields["sig_info"]

        return ClubLogFetchedQSO(
            callsign: callsign.uppercased(),
            band: band.lowercased(),
            mode: mode.uppercased(),
            frequency: frequency,
            timestamp: timestamp,
            rstSent: fields["rst_sent"],
            rstReceived: fields["rst_rcvd"],
            myCallsign: fields["station_callsign"],
            myGrid: fields["my_gridsquare"],
            theirGrid: fields["gridsquare"],
            parkReference: myParkRef,
            theirParkReference: theirParkRef,
            notes: fields["comment"],
            dxcc: dxcc,
            rawADIF: record
        )
    }
}

// MARK: - Network Helpers

extension ClubLogClient {
    /// Build multipart form data for ADIF upload
    func buildMultipartBody(
        boundary: String, fields: [String: String], adifContent: String
    ) -> Data {
        var body = Data()

        for (key, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        // Add file field
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"file\"; filename=\"upload.adi\"\r\n".utf8
        ))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(Data(adifContent.utf8))
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        return body
    }

    /// Perform a POST request with form-encoded parameters
    func performPostRequest(
        url urlString: String,
        params: [String: String],
        useApiKey: Bool,
        contentType: String = "application/x-www-form-urlencoded"
    ) async throws -> (Data, URLResponse) {
        guard let url = URL(string: urlString) else {
            throw ClubLogError.invalidResponse("Invalid URL: \(urlString)")
        }

        var allParams = params
        if useApiKey {
            allParams["api"] = try getApiKey()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncode(allParams).utf8)

        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw ClubLogError.networkError(error)
        }
    }

    /// Form-encode a dictionary for POST body
    func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")

        return params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}
