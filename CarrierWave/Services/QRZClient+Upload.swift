import Foundation

// MARK: - QRZClient Upload Helpers

extension QRZClient {
    /// Execute QRZ upload request with response logging
    func executeQRZUpload(
        request: URLRequest, adifChars: Int, qsoCount: Int, bookId: String?
    ) async throws -> (uploaded: Int, duplicates: Int) {
        let debugLog = SyncDebugLog.shared
        await MainActor.run {
            debugLog.debug(
                "QRZ upload request: \(qsoCount) QSO(s), "
                    + "ADIF \(adifChars) chars, bookId=\(bookId ?? "nil")",
                service: .qrz
            )
        }

        let uploadStart = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int(Date().timeIntervalSince(uploadStart) * 1_000)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode

        guard let responseString = String(data: data, encoding: .utf8) else {
            await MainActor.run {
                debugLog.error(
                    "QRZ response: HTTP \(httpStatus ?? 0) (\(durationMs)ms) "
                        + "- cannot decode \(data.count) bytes as UTF-8",
                    service: .qrz
                )
            }
            throw QRZError.invalidResponse(
                "Cannot decode response as UTF-8, \(data.count) bytes"
            )
        }

        await MainActor.run {
            let level: SyncDebugLog.LogEntry.Level =
                httpStatus.map { (200 ... 299).contains($0) } == true ? .debug : .error
            debugLog.log(
                "QRZ response: HTTP \(httpStatus ?? 0) (\(durationMs)ms) "
                    + "\(responseString.prefix(500))",
                level: level, service: .qrz
            )
        }

        return try parseUploadResponse(responseString)
    }

    /// Filter QSOs to only those matching the QRZ account callsign
    func filterQSOsForUpload(
        _ qsos: [QSO], accountCallsign: String?
    ) -> (matching: [QSO], skippedCount: Int) {
        guard let accountCallsign else {
            return (qsos, 0)
        }

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

    /// Build the upload request with proper headers and form data
    func buildUploadRequest(
        apiKey: String, adifContent: String, bookId: String?
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var formData = [
            "KEY": apiKey, "ACTION": "INSERT", "OPTION": "REPLACE", "ADIF": adifContent,
        ]
        if let bookId {
            formData["BOOKID"] = bookId
        }
        request.httpBody = formEncode(formData).data(using: .utf8)
        return request
    }

    /// Parse the upload response and return counts or throw appropriate error
    func parseUploadResponse(_ responseString: String) throws -> (
        uploaded: Int, duplicates: Int
    ) {
        let parsed = Self.parseResponse(responseString)

        if parsed["RESULT"] == "AUTH" {
            throw QRZError.sessionExpired
        }

        let result = parsed["RESULT"] ?? ""
        guard result == "OK" || result == "REPLACE" || result == "PARTIAL" else {
            let reason = parsed["REASON"] ?? "Response: \(responseString.prefix(200))"
            throw QRZError.uploadFailed(reason)
        }

        let count = Int(parsed["COUNT"] ?? "0") ?? 0
        let dupes = Int(parsed["DUPES"] ?? "0") ?? 0
        let reason = parsed["REASON"]

        if result == "PARTIAL" {
            Task { @MainActor in
                SyncDebugLog.shared.warning(
                    "QRZ PARTIAL upload: \(count) accepted, \(dupes) dupes"
                        + (reason.map { ", reason=\($0)" } ?? ""),
                    service: .qrz
                )
            }
        }

        return (uploaded: count, duplicates: dupes)
    }
}
