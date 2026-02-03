import Foundation

// MARK: - LoTWClient ADIF Parsing

@MainActor
extension LoTWClient {
    /// Parse ADIF response string into LoTWResponse
    func parseADIFResponse(_ adif: String) -> LoTWResponse {
        var qsos: [LoTWFetchedQSO] = []
        var lastQSL: Date?
        var lastQSORx: Date?
        var recordCount = 0

        // Parse header for metadata
        if let headerEnd = adif.range(of: "<EOH>", options: .caseInsensitive) {
            let header = String(adif[..<headerEnd.lowerBound])
            lastQSL = parseHeaderDate(header, field: "APP_LoTW_LASTQSL")
            lastQSORx = parseHeaderDate(header, field: "APP_LoTW_LASTQSORX")
            if let count = parseHeaderField(header, field: "APP_LoTW_NUMREC") {
                recordCount = Int(count) ?? 0
            }
        }

        // Split into records (case-insensitive - LoTW uses lowercase <eor>)
        let records = adif.components(separatedBy: "<eor>")
            .flatMap { $0.components(separatedBy: "<EOR>") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains("<") }

        for record in records {
            // Skip header
            if record.uppercased().contains("<EOH>") {
                continue
            }

            if let qso = parseQSORecord(record) {
                qsos.append(qso)
            }
        }

        return LoTWResponse(
            qsos: qsos,
            lastQSL: lastQSL,
            lastQSORx: lastQSORx,
            recordCount: recordCount
        )
    }

    // MARK: - Header Parsing

    func parseHeaderField(_ header: String, field: String) -> String? {
        let pattern = "<\(field):([0-9]+)>([^<]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: header, range: NSRange(header.startIndex..., in: header)
              ),
              let valueRange = Range(match.range(at: 2), in: header)
        else {
            return nil
        }
        return String(header[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parseHeaderDate(_ header: String, field: String) -> Date? {
        guard let value = parseHeaderField(header, field: field) else {
            return nil
        }
        // Format: YYYY-MM-DD HH:MM:SS
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: value)
    }

    // MARK: - Field Extraction

    func extractField(_ name: String, from record: String) -> String? {
        let pattern = "<\(name):([0-9]+)>([^<]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: record, range: NSRange(record.startIndex..., in: record)
              ),
              let valueRange = Range(match.range(at: 2), in: record)
        else {
            return nil
        }
        let value = String(record[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - QSO Parsing

    func parseQSOTimestamp(dateStr: String, timeStr: String?) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMddHHmm"
        let timeOnStr = timeStr ?? "0000"
        let dateTimeStr = dateStr + timeOnStr.prefix(4)
        return dateFormatter.date(from: dateTimeStr)
    }

    func parseQSLReceivedDate(_ record: String) -> Date? {
        guard let qslDateStr = extractField("QSLRDATE", from: record) else {
            return nil
        }
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd"
        return dateFormatter.date(from: qslDateStr)
    }

    func parseQSORecord(_ record: String) -> LoTWFetchedQSO? {
        guard let callsign = extractField("CALL", from: record),
              let band = extractField("BAND", from: record),
              let qsoDateStr = extractField("QSO_DATE", from: record),
              let timestamp = parseQSOTimestamp(
                  dateStr: qsoDateStr, timeStr: extractField("TIME_ON", from: record)
              )
        else {
            return nil
        }

        // LoTW may emit APP_LoTW_MODE instead of (or in addition to) MODE when the mode
        // can't be cleanly mapped to standard ADIF. Prefer MODE but fall back to APP_LoTW_MODE.
        guard
            let mode = extractField("MODE", from: record)
            ?? extractField("APP_LoTW_MODE", from: record)
        else {
            return nil
        }

        let qslReceived = extractField("QSL_RCVD", from: record)?.uppercased() == "Y"

        return LoTWFetchedQSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: extractField("FREQ", from: record).flatMap { Double($0) },
            timestamp: timestamp,
            rstSent: extractField("RST_SENT", from: record),
            rstReceived: extractField("RST_RCVD", from: record),
            myCallsign: extractField("STATION_CALLSIGN", from: record)
                ?? extractField("APP_LoTW_OWNCALL", from: record),
            myGrid: extractField("MY_GRIDSQUARE", from: record),
            theirGrid: extractField("GRIDSQUARE", from: record),
            state: extractField("STATE", from: record),
            country: extractField("COUNTRY", from: record),
            dxcc: extractField("DXCC", from: record).flatMap { Int($0) },
            qslReceived: qslReceived,
            qslReceivedDate: parseQSLReceivedDate(record),
            rawADIF: record
        )
    }
}
