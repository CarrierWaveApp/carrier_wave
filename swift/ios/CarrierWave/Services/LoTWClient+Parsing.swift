import CarrierWaveData
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
        ADIFParser.extractField(field, from: header)
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
        ADIFParser.extractField(name, from: record)
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

    private func parseQSLDateString(_ dateStr: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd"
        return dateFormatter.date(from: dateStr)
    }

    func parseQSORecord(_ record: String) -> LoTWFetchedQSO? {
        let fields = ADIFParser.extractFields(record)

        guard let callsign = fields["call"],
              let band = fields["band"],
              let qsoDateStr = fields["qso_date"],
              let timestamp = parseQSOTimestamp(
                  dateStr: qsoDateStr, timeStr: fields["time_on"]
              )
        else {
            return nil
        }

        // LoTW may emit APP_LoTW_MODE instead of (or in addition to) MODE
        guard let mode = fields["mode"] ?? fields["app_lotw_mode"] else {
            return nil
        }

        let qslReceived = fields["qsl_rcvd"]?.uppercased() == "Y"
        let qslDate = fields["qslrdate"].flatMap { parseQSLDateString($0) }

        return LoTWFetchedQSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: fields["freq"].flatMap { Double($0) },
            timestamp: timestamp,
            rstSent: fields["rst_sent"],
            rstReceived: fields["rst_rcvd"],
            myCallsign: fields["station_callsign"]
                ?? fields["app_lotw_owncall"],
            myGrid: fields["my_gridsquare"],
            theirGrid: fields["gridsquare"],
            state: fields["state"],
            country: fields["country"],
            dxcc: fields["dxcc"].flatMap { Int($0) },
            qslReceived: qslReceived,
            qslReceivedDate: qslDate,
            rawADIF: record
        )
    }
}
