import CarrierWaveData
import Foundation

// MARK: - QRZClient Fetch Helpers

extension QRZClient {
    /// Build a fetch request for the QRZ API.
    /// - Parameters:
    ///   - since: If provided, adds MODSINCE filter for incremental sync
    ///   - extraOptions: Additional option parts (e.g. "STATUS:CONFIRMED")
    func buildFetchRequest(
        url: URL, apiKey: String, afterLogId: Int64, pageSize: Int,
        since: Date? = nil, extraOptions: [String] = []
    ) -> URLRequest {
        var optionParts = ["MAX:\(pageSize)", "AFTERLOGID:\(afterLogId)"]
        if let since {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            optionParts.append("MODSINCE:\(formatter.string(from: since))")
        }
        optionParts.append(contentsOf: extraOptions)

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

    /// Fetch confirmed QSO log IDs from QRZ using TYPE:LOGIDS.
    /// Returns only the set of qrzLogId strings for confirmed records — much lighter
    /// than fetching full ADIF for every confirmed QSO.
    func fetchConfirmedLogIds() async throws -> Set<String> {
        let apiKey = try getApiKey()
        var confirmedIds = Set<String>()
        var afterLogId: Int64 = 0
        let pageSize = 10_000

        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        while true {
            let request = buildLogIdsRequest(
                url: url, apiKey: apiKey,
                afterLogId: afterLogId, pageSize: pageSize
            )

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "nil"
                throw QRZError.invalidResponse(
                    "HTTP \(httpResponse.statusCode), body: \(bodyPreview)"
                )
            }

            let parsed = try parseLogIdsResponse(data)
            guard let pageResult = processLogIdsPage(parsed, pageSize: pageSize) else {
                break
            }

            confirmedIds.formUnion(pageResult.ids)
            if let nextAfter = pageResult.nextAfterLogId {
                afterLogId = nextAfter
            } else {
                break
            }

            try await Task.sleep(nanoseconds: 200_000_000)
        }

        NSLog("[QRZ] Confirmed log IDs fetch complete: %d IDs", confirmedIds.count)
        return confirmedIds
    }

    private func buildLogIdsRequest(
        url: URL, apiKey: String, afterLogId: Int64, pageSize: Int
    ) -> URLRequest {
        let optionParts = [
            "MAX:\(pageSize)", "AFTERLOGID:\(afterLogId)",
            "STATUS:CONFIRMED", "TYPE:LOGIDS",
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let formData = [
            "KEY": apiKey, "ACTION": "FETCH",
            "OPTION": optionParts.joined(separator: ","),
        ]
        request.httpBody = formEncode(formData).data(using: .utf8)
        return request
    }

    private func parseLogIdsResponse(_ data: Data) throws -> [String: String] {
        let responseString = try decodeResponseData(data)
        let parsed = Self.parseResponse(responseString)
        if parsed["RESULT"] == "AUTH" {
            throw QRZError.sessionExpired
        }
        return parsed
    }

    private struct LogIdsPageResult {
        let ids: [String]
        let nextAfterLogId: Int64?
    }

    private func processLogIdsPage(
        _ parsed: [String: String], pageSize: Int
    ) -> LogIdsPageResult? {
        let result = parsed["RESULT"] ?? ""
        let reason = parsed["REASON"]?.lowercased() ?? ""
        let count = Int(parsed["COUNT"] ?? "") ?? 0

        if reason.contains("no log entries found") || (result == "FAIL" && count == 0) {
            return nil
        }

        guard result == "OK",
              let logIds = parsed["LOGIDS"], !logIds.isEmpty
        else {
            return nil
        }

        let ids = logIds.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        let maxId = ids.compactMap { Int64($0) }.max() ?? 0
        let hasMore = ids.count >= pageSize && maxId > 0
        return LogIdsPageResult(
            ids: ids, nextAfterLogId: hasMore ? maxId + 1 : nil
        )
    }

    /// Fetch specific QSOs from QRZ by their log IDs using LOGIDS option.
    /// Used to backfill qrzLogId and qrzConfirmed for QSOs that were uploaded
    /// before the LOGID capture fix.
    func fetchQSOsByLogIds(_ logIds: [String]) async throws -> [QRZFetchedQSO] {
        guard !logIds.isEmpty else {
            return []
        }

        let apiKey = try getApiKey()
        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        var allQSOs: [QRZFetchedQSO] = []
        let batchSize = 100

        // Fetch in batches to avoid overly long OPTION strings
        for batchStart in stride(from: 0, to: logIds.count, by: batchSize) {
            try Task.checkCancellation()
            let batchEnd = min(batchStart + batchSize, logIds.count)
            let batch = logIds[batchStart ..< batchEnd]
            let logIdsParam = batch.joined(separator: "+")

            let optionParts = ["LOGIDS:\(logIdsParam)"]
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )
            let formData = [
                "KEY": apiKey, "ACTION": "FETCH",
                "OPTION": optionParts.joined(separator: ","),
            ]
            request.httpBody = formEncode(formData).data(using: .utf8)

            let (qsos, _) = try await fetchQSOPage(request: request)
            allQSOs.append(contentsOf: qsos)

            if batchEnd < logIds.count {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        NSLog(
            "[QRZ] Fetched %d QSOs by log IDs for backfill",
            allQSOs.count
        )
        return allQSOs
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
