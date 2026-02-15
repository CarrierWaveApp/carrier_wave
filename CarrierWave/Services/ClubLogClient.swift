import CarrierWaveCore
import Foundation

// MARK: - ClubLogError

enum ClubLogError: Error, LocalizedError {
    case authenticationFailed
    case forbidden
    case uploadFailed(String)
    case uploadRejected(String)
    case fetchFailed(String)
    case networkError(Error)
    case invalidResponse(String)
    case notConfigured
    case serverError(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            "Club Log authentication failed. Check your email and app password."
        case .forbidden:
            "Club Log returned 403 Forbidden. Credentials may be invalid — "
                + "do NOT retry (repeated 403s will get your IP blocked)."
        case let .uploadFailed(reason):
            "Club Log upload failed: \(reason)"
        case let .uploadRejected(reason):
            "Club Log rejected QSO: \(reason)"
        case let .fetchFailed(reason):
            "Club Log fetch failed: \(reason)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(details):
            "Invalid response from Club Log: \(details)"
        case .notConfigured:
            "Club Log is not configured. Add your email and app password in Settings."
        case let .serverError(details):
            "Club Log server error: \(details)"
        }
    }
}

// MARK: - ClubLogFetchedQSO

/// A QSO fetched from Club Log via ADIF download
struct ClubLogFetchedQSO {
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String?
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let theirParkReference: String?
    let notes: String?
    let dxcc: Int?
    let rawADIF: String
}

// MARK: - ClubLogUploadResult

struct ClubLogUploadResult {
    let uploaded: Int
    let skipped: Int
}

// MARK: - ClubLogClient

@MainActor
final class ClubLogClient {
    // MARK: Internal

    let keychain = KeychainHelper.shared
    let userAgent = "CarrierWave/1.0"

    // MARK: - Credential Management

    func saveCredentials(email: String, password: String, callsign: String) throws {
        try keychain.save(email, for: KeychainHelper.Keys.clublogEmail)
        try keychain.save(password, for: KeychainHelper.Keys.clublogPassword)
        try keychain.save(callsign.uppercased(), for: KeychainHelper.Keys.clublogCallsign)
    }

    func saveApiKey(_ key: String) throws {
        try keychain.save(key, for: KeychainHelper.Keys.clublogApiKey)
    }

    func getApiKey() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.clublogApiKey)
    }

    func getEmail() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.clublogEmail)
    }

    func getPassword() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.clublogPassword)
    }

    func getCallsign() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.clublogCallsign)
    }

    func hasCredentials() -> Bool {
        getEmail() != nil && getPassword() != nil && getCallsign() != nil
    }

    var isConfigured: Bool {
        hasCredentials() && (try? getApiKey()) != nil
    }

    func logout() {
        try? keychain.delete(for: KeychainHelper.Keys.clublogApiKey)
        try? keychain.delete(for: KeychainHelper.Keys.clublogEmail)
        try? keychain.delete(for: KeychainHelper.Keys.clublogPassword)
        try? keychain.delete(for: KeychainHelper.Keys.clublogCallsign)
        try? keychain.delete(for: KeychainHelper.Keys.clublogLastDownloadDate)
    }

    // MARK: - Sync Timestamps

    func getLastDownloadDate() -> Date? {
        guard let dateString = try? keychain.readString(
            for: KeychainHelper.Keys.clublogLastDownloadDate
        ) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: dateString)
    }

    func saveLastDownloadDate(_ date: Date) {
        let dateString = ISO8601DateFormatter().string(from: date)
        try? keychain.save(dateString, for: KeychainHelper.Keys.clublogLastDownloadDate)
    }

    func clearLastDownloadDate() {
        try? keychain.delete(for: KeychainHelper.Keys.clublogLastDownloadDate)
    }

    // MARK: - API Methods

    /// Validate credentials by attempting a small download
    func validateCredentials(
        email: String, password: String, callsign: String
    ) async throws {
        // Test by downloading recent QSOs (last 7 days)
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now)!
        let comps = cal.dateComponents([.year, .month, .day], from: weekAgo)

        var params: [String: String] = [
            "email": email,
            "password": password,
            "call": callsign.uppercased(),
        ]
        if let year = comps.year { params["startyear"] = String(year) }
        if let month = comps.month { params["startmonth"] = String(month) }
        if let day = comps.day { params["startday"] = String(day) }

        let (_, response) = try await performPostRequest(
            url: "https://clublog.org/getadif.php",
            params: params,
            useApiKey: false
        )

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 {
                throw ClubLogError.forbidden
            }
            if httpResponse.statusCode != 200 {
                throw ClubLogError.authenticationFailed
            }
        }
    }

    /// Download QSOs from Club Log as ADIF
    /// - Parameters:
    ///   - since: Optional date to filter (startyear/startmonth/startday)
    func fetchQSOs(since: Date? = nil) async throws -> [ClubLogFetchedQSO] {
        guard let email = getEmail(),
              let password = getPassword(),
              let callsign = getCallsign()
        else {
            throw ClubLogError.notConfigured
        }

        var params: [String: String] = [
            "email": email,
            "password": password,
            "call": callsign,
        ]

        if let since {
            let cal = Calendar(identifier: .gregorian)
            let comps = cal.dateComponents([.year, .month, .day], from: since)
            if let year = comps.year { params["startyear"] = String(year) }
            if let month = comps.month { params["startmonth"] = String(month) }
            if let day = comps.day { params["startday"] = String(day) }
        }

        let (data, response) = try await performPostRequest(
            url: "https://clublog.org/getadif.php",
            params: params,
            useApiKey: false
        )

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
            throw ClubLogError.forbidden
        }

        guard let adifString = String(data: data, encoding: .utf8) else {
            throw ClubLogError.invalidResponse("Cannot decode response as UTF-8")
        }

        // Check for error responses (Club Log returns plain text errors)
        if adifString.lowercased().contains("invalid") && !adifString.contains("<EOH>")
            && !adifString.contains("<eoh>")
        {
            throw ClubLogError.authenticationFailed
        }

        return parseADIFRecords(adifString)
    }

    /// Upload QSOs to Club Log via batch ADIF upload (putlogs.php)
    func uploadQSOs(_ qsos: [QSO]) async throws -> ClubLogUploadResult {
        guard !qsos.isEmpty else {
            return ClubLogUploadResult(uploaded: 0, skipped: 0)
        }

        guard let email = getEmail(),
              let password = getPassword(),
              let callsign = getCallsign()
        else {
            throw ClubLogError.notConfigured
        }

        let apiKey = try getApiKey()
        let accountCallsign = callsign.uppercased()

        // Filter to matching callsign
        let (matchingQSOs, skippedCount) = filterQSOsForUpload(
            qsos, accountCallsign: accountCallsign
        )

        guard !matchingQSOs.isEmpty else {
            return ClubLogUploadResult(uploaded: 0, skipped: skippedCount)
        }

        // Generate ADIF content
        let adifContent = matchingQSOs.map { qso in
            qso.rawADIF ?? generateADIF(for: qso)
        }.joined(separator: "\n")

        // Build multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add form fields
        let fields: [String: String] = [
            "email": email,
            "password": password,
            "callsign": accountCallsign,
            "api": apiKey,
        ]

        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!
            )
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"upload.adi\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(adifContent.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        guard let url = URL(string: "https://clublog.org/putlogs.php") else {
            throw ClubLogError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 {
                throw ClubLogError.forbidden
            }
            if httpResponse.statusCode != 200 {
                throw ClubLogError.uploadFailed("HTTP \(httpResponse.statusCode)")
            }
        }

        return ClubLogUploadResult(uploaded: matchingQSOs.count, skipped: skippedCount)
    }

    /// Upload a single QSO in real-time (realtime.php)
    func uploadSingleQSO(_ qso: QSO) async throws {
        guard let email = getEmail(),
              let password = getPassword(),
              let callsign = getCallsign()
        else {
            throw ClubLogError.notConfigured
        }

        let apiKey = try getApiKey()
        let adifRecord = qso.rawADIF ?? generateADIF(for: qso)

        let params: [String: String] = [
            "email": email,
            "password": password,
            "callsign": callsign.uppercased(),
            "api": apiKey,
            "adif": adifRecord,
        ]

        let (data, response) = try await performPostRequest(
            url: "https://clublog.org/realtime.php",
            params: params,
            useApiKey: false,
            contentType: "application/x-www-form-urlencoded"
        )

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 403 {
                throw ClubLogError.forbidden
            }
            if httpResponse.statusCode == 400 {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ClubLogError.uploadRejected(body)
            }
            if httpResponse.statusCode == 500 {
                throw ClubLogError.serverError("Internal server error — retry later")
            }
        }
    }

    // MARK: - ADIF Parsing

    /// Parse ADIF string into ClubLogFetchedQSO records
    func parseADIFRecords(_ adif: String) -> [ClubLogFetchedQSO] {
        // Skip header (everything before first <EOH> or <eoh>)
        let headerEnd: String.Index
        if let eohRange = adif.range(of: "<EOH>", options: .caseInsensitive) {
            headerEnd = eohRange.upperBound
        } else {
            headerEnd = adif.startIndex
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

    // MARK: Private

    /// Parse a single ADIF record into a ClubLogFetchedQSO
    private func parseADIFRecord(_ record: String) -> ClubLogFetchedQSO? {
        let fields = parseADIFFields(record)

        guard let callsign = fields["CALL"] ?? fields["call"],
              let band = fields["BAND"] ?? fields["band"],
              let mode = fields["MODE"] ?? fields["mode"]
        else {
            return nil
        }

        let timestamp = parseTimestamp(
            date: fields["QSO_DATE"] ?? fields["qso_date"],
            time: fields["TIME_ON"] ?? fields["time_on"]
        ) ?? Date()

        var frequency: Double?
        if let freqStr = fields["FREQ"] ?? fields["freq"], let freq = Double(freqStr) {
            frequency = freq
        }

        let dxcc = (fields["DXCC"] ?? fields["dxcc"]).flatMap { Int($0) }

        let myParkRef = fields["MY_SIG_INFO"] ?? fields["my_sig_info"]
            ?? fields["MY_POTA_REF"] ?? fields["my_pota_ref"]
        let theirParkRef = fields["SIG_INFO"] ?? fields["sig_info"]

        return ClubLogFetchedQSO(
            callsign: callsign.uppercased(),
            band: band.uppercased(),
            mode: mode.uppercased(),
            frequency: frequency,
            timestamp: timestamp,
            rstSent: fields["RST_SENT"] ?? fields["rst_sent"],
            rstReceived: fields["RST_RCVD"] ?? fields["rst_rcvd"],
            myCallsign: fields["STATION_CALLSIGN"] ?? fields["station_callsign"],
            myGrid: fields["MY_GRIDSQUARE"] ?? fields["my_gridsquare"],
            theirGrid: fields["GRIDSQUARE"] ?? fields["gridsquare"],
            parkReference: myParkRef,
            theirParkReference: theirParkRef,
            notes: fields["COMMENT"] ?? fields["comment"],
            dxcc: dxcc,
            rawADIF: record
        )
    }

    /// Parse ADIF fields from a record string
    private func parseADIFFields(_ record: String) -> [String: String] {
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
    private func parseTimestamp(date: String?, time: String?) -> Date? {
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

    /// Generate ADIF for a QSO
    private func generateADIF(for qso: QSO) -> String {
        var fields: [String] = []

        func addField(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else {
                return
            }
            fields.append("<\(name):\(value.count)>\(value)")
        }

        addField("CALL", qso.callsign)
        addField("BAND", qso.band)
        addField("MODE", qso.mode)

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
        addField("STATION_CALLSIGN", qso.myCallsign)
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
        addField("COMMENT", qso.notes)

        return fields.joined(separator: " ") + " <EOR>"
    }

    /// Filter QSOs to only those matching the account callsign
    private func filterQSOsForUpload(
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

    /// Perform a POST request with form-encoded parameters
    private func performPostRequest(
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
        request.httpBody = formEncode(allParams).data(using: .utf8)

        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw ClubLogError.networkError(error)
        }
    }

    /// Form-encode a dictionary for POST body
    private func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")

        return params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }
}
