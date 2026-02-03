import Foundation

// MARK: - QRZClient Fetch Helpers

extension QRZClient {
    /// Build a fetch request for the QRZ API
    func buildFetchRequest(
        url: URL, apiKey: String, afterLogId: Int64, pageSize: Int, since: Date?
    ) -> URLRequest {
        // Use AFTERLOGID for pagination (OFFSET doesn't work in QRZ API)
        var optionParts = ["MAX:\(pageSize)", "AFTERLOGID:\(afterLogId)"]
        if let since {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            optionParts.append("MODSINCE:\(formatter.string(from: since))")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let formData = [
            "KEY": apiKey, "ACTION": "FETCH", "OPTION": optionParts.joined(separator: ","),
        ]
        request.httpBody = formEncode(formData).data(using: .utf8)
        return request
    }

    /// Fetch a single page of QSOs from QRZ
    func fetchQSOPage(request: URLRequest) async throws -> ([QRZFetchedQSO], Int) {
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "nil"
            throw QRZError.invalidResponse("HTTP \(httpResponse.statusCode), body: \(bodyPreview)")
        }

        let responseString = try decodeResponseData(data)
        let parsed = Self.parseResponse(responseString)

        if parsed["RESULT"] == "AUTH" {
            throw QRZError.sessionExpired
        }

        let result = parsed["RESULT"] ?? ""
        let reason = parsed["REASON"]?.lowercased() ?? ""
        let responseCount = Int(parsed["COUNT"] ?? "") ?? 0

        if reason.contains("no log entries found") || (result == "FAIL" && responseCount == 0) {
            return ([], 0)
        }

        guard result == "OK" else {
            let errorReason =
                parsed["REASON"] ?? "RESULT=\(result), Response: \(responseString.prefix(300))"
            throw QRZError.fetchFailed(errorReason)
        }

        guard let encodedADIF = parsed["ADIF"] else {
            return ([], 0)
        }

        let adif = decodeADIF(encodedADIF)
        return (parseADIFRecords(adif), responseCount)
    }

    /// Decode response data from QRZ, handling different encodings
    func decodeResponseData(_ data: Data) throws -> String {
        if let utf8String = String(data: data, encoding: .utf8) {
            return utf8String
        }
        if let latin1String = String(data: data, encoding: .isoLatin1) {
            return latin1String
        }
        let firstBytes = data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
        throw QRZError.invalidResponse(
            "Cannot decode \(data.count) bytes, first bytes: \(firstBytes)"
        )
    }
}
