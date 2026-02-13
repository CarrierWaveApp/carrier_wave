import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - POTAUploadRequestData

struct POTAUploadRequestData {
    let request: URLRequest
    let filename: String
    let adifContent: String
    let location: String
    let callsign: String
    let qsoCount: Int
}

// MARK: - POTAFormFields

struct POTAFormFields {
    let parkReference: String
    let location: String
    let callsign: String
}

extension POTAClient {
    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Validate park reference format (e.g., "K-1234", "VE-1234", "US-1234")
    func validateParkReference(_ parkReference: String) -> Bool {
        let parkPattern = #"^[A-Za-z]{1,4}-\d{1,6}$"#
        return parkReference.range(of: parkPattern, options: .regularExpression) != nil
    }

    /// Build upload request data
    func buildUploadRequest(
        parkReference: String,
        qsos: [QSO],
        token: String
    ) -> POTAUploadRequestData? {
        let debugLog = SyncDebugLog.shared
        let normalizedParkRef = parkReference.uppercased()

        debugLog.debug(
            "buildUploadRequest: park=\(normalizedParkRef), input QSOs=\(qsos.count)",
            service: .pota
        )

        let parkQSOs = filterQSOsForPark(qsos, parkRef: normalizedParkRef)
        guard !parkQSOs.isEmpty else {
            debugLog.info("No QSOs to upload for park \(normalizedParkRef)", service: .pota)
            return nil
        }

        let callsign =
            parkQSOs.first(where: { !$0.myCallsign.isEmpty })?.myCallsign
                ?? CallsignAliasService.shared.getCurrentCallsign() ?? "UNKNOWN"
        let grid = parkQSOs.first?.myGrid
        let location = deriveLocation(parkReference: normalizedParkRef, grid: grid)
        warnIfLocationMismatch(
            parkReference: normalizedParkRef, derivedLocation: location, grid: grid
        )
        let adifContent = generateADIF(
            for: parkQSOs, parkReference: normalizedParkRef, activatorCallsign: callsign
        )
        let filename = buildFilename(
            callsign: callsign, parkReference: normalizedParkRef, qsos: parkQSOs
        )
        let formFields = POTAFormFields(
            parkReference: normalizedParkRef, location: location, callsign: callsign
        )
        SyncDebugLog.shared.info(
            "ADIF for \(normalizedParkRef): \(adifContent.count) chars, \(parkQSOs.count) QSOs, "
                + "callsign=\(callsign), location=\(location), filename=\(filename)",
            service: .pota
        )

        guard
            let request = buildMultipartRequest(
                token: token, filename: filename, adifContent: adifContent, formFields: formFields
            )
        else {
            debugLog.error("Invalid URL for POTA upload", service: .pota)
            return nil
        }

        return POTAUploadRequestData(
            request: request, filename: filename, adifContent: adifContent,
            location: location, callsign: callsign, qsoCount: parkQSOs.count
        )
    }

    /// Filter QSOs for a specific park, excluding metadata modes
    private func filterQSOsForPark(_ qsos: [QSO], parkRef: String) -> [QSO] {
        // Uses hasOverlap to support multi-park/two-fer references (e.g., "US-1044, US-3791")
        qsos.filter {
            guard let ref = $0.parkReference else {
                return false
            }
            return ParkReference.hasOverlap(ref, parkRef)
                && !Self.metadataModes.contains($0.mode.uppercased())
        }
    }

    /// Validate park reference and return normalized (uppercased) version
    func validateAndNormalizePark(_ parkReference: String) throws -> String {
        guard validateParkReference(parkReference) else {
            SyncDebugLog.shared.error(
                "Invalid park reference format: '\(parkReference)' (expected format like K-1234)",
                service: .pota
            )
            throw POTAError.invalidParkReference
        }
        return parkReference.uppercased()
    }

    /// Acquire auth token with debug logging
    func acquireTokenWithLogging(for parkRef: String) async throws -> String {
        let debugLog = SyncDebugLog.shared
        debugLog.debug("Requesting auth token for POTA upload (park \(parkRef))", service: .pota)

        let token: String
        do {
            token = try await authService.ensureValidToken()
        } catch {
            debugLog.error(
                "Failed to get POTA auth token: \(error.localizedDescription)", service: .pota
            )
            throw error
        }

        let tokenPrefix = String(token.prefix(20))
        debugLog.debug(
            "Got POTA token: len=\(token.count), prefix=\(tokenPrefix)...", service: .pota
        )
        return token
    }

    /// Filter QSOs that match a specific park reference (without metadata mode exclusion)
    func filterQSOsForParkRef(_ qsos: [QSO], parkRef: String) -> [QSO] {
        let parkQSOs = qsos.filter {
            guard let ref = $0.parkReference else {
                return false
            }
            return ParkReference.hasOverlap(ref, parkRef)
        }
        SyncDebugLog.shared.debug(
            "Filtered \(qsos.count) input QSOs to \(parkQSOs.count) for park \(parkRef)",
            service: .pota
        )
        return parkQSOs
    }

    /// Log request details before sending
    func logUploadRequestDetails(_ data: POTAUploadRequestData, parkRef: String) {
        let debugLog = SyncDebugLog.shared
        debugLog.info(
            "Uploading \(data.qsoCount) QSOs to park \(parkRef): "
                + "POST \(data.request.url?.absoluteString ?? "nil") "
                + "callsign=\(data.callsign), location=\(data.location), "
                + "file=\(data.filename), bodySize=\(data.request.httpBody?.count ?? 0) bytes",
            service: .pota
        )
    }

    func deriveLocation(parkReference: String, grid: String?) -> String {
        // Use parks cache for accurate location (grid derivation is unreliable near state borders)
        if let cachedPark = POTAParksCache.shared.parkSync(for: parkReference),
           !cachedPark.locationDesc.isEmpty
        {
            // For multi-state parks (e.g., "US-AZ,US-CA"), use the first location
            let location = cachedPark.locationDesc.split(separator: ",").first
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            if let location, !location.isEmpty {
                return location
            }
        }

        // Fallback: derive from grid square (kept for offline/cache-miss scenarios)
        let parkPrefix = parkReference.split(separator: "-").first.map(String.init) ?? "US"
        let derivedState = grid.flatMap { Self.gridToUSState($0) }
        if parkPrefix == "US" || parkPrefix == "K", let state = derivedState {
            return "US-\(state)"
        }
        return parkPrefix
    }

    /// Warn if the grid-derived state doesn't match the park's known location(s).
    /// This catches cases where the operator's grid is wrong or in a different state than the park.
    private func warnIfLocationMismatch(
        parkReference: String, derivedLocation: String, grid: String?
    ) {
        guard let cachedPark = POTAParksCache.shared.parkSync(for: parkReference) else {
            return
        }
        let parkLocations = cachedPark.locationDesc
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !parkLocations.isEmpty else {
            return
        }

        // Compare the grid-derived state against the park's known states
        let gridState = grid.flatMap { Self.gridToUSState($0) }.map { "US-\($0)" }
        if let gridState, !parkLocations.contains(gridState) {
            SyncDebugLog.shared.warning(
                "Location mismatch for \(parkReference): operator grid \(grid ?? "?") "
                    + "maps to \(gridState), but park is in \(parkLocations.joined(separator: ", ")). "
                    + "Using park location \(derivedLocation) for upload.",
                service: .pota
            )
        }
    }

    private func buildFilename(callsign: String, parkReference: String, qsos: [QSO]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = qsos.first.map { dateFormatter.string(from: $0.timestamp) } ?? "000000"
        return "\(callsign)@\(parkReference)-\(dateStr).adi"
    }

    private func buildMultipartRequest(
        token: String, filename: String, adifContent: String, formFields: POTAFormFields
    ) -> URLRequest? {
        let boundary = UUID().uuidString
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(
            Data("Content-Disposition: form-data; name=\"adif\"; filename=\"\(filename)\"\r\n".utf8)
        )
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(Data(adifContent.utf8))
        body.append(Data("\r\n".utf8))

        let fields = [
            ("reference", formFields.parkReference),
            ("location", formFields.location),
            ("callsign", formFields.callsign),
        ]
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        guard let url = URL(string: "\(baseURL)/adif") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        return request
    }

    /// Create upload attempt record
    @MainActor
    func createUploadAttempt(
        startTime: Date,
        parkReference: String,
        requestData: POTAUploadRequestData,
        modelContext: ModelContext
    ) -> POTAUploadAttempt {
        let recordedHeaders = [
            "Content-Type": requestData.request.value(forHTTPHeaderField: "Content-Type") ?? "",
            "Authorization": "[REDACTED]",
        ]

        let attempt = POTAUploadAttempt(
            timestamp: startTime, parkReference: parkReference,
            qsoCount: requestData.qsoCount, callsign: requestData.callsign,
            location: requestData.location, adifContent: requestData.adifContent,
            requestHeaders: recordedHeaders, filename: requestData.filename
        )
        modelContext.insert(attempt)
        return attempt
    }

    /// Execute upload request and record result
    func executeUploadWithRecording(
        request: URLRequest,
        attempt: POTAUploadAttempt,
        startTime: Date,
        parkReference: String,
        qsoCount: Int
    ) async throws -> POTAUploadResult {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Sending POTA upload request for \(parkReference)...", service: .pota)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1_000)

            guard let httpResponse = response as? HTTPURLResponse else {
                debugLog.error(
                    "POTA upload response is not HTTP for \(parkReference) (\(durationMs)ms)",
                    service: .pota
                )
                await recordAttemptFailure(
                    attempt, statusCode: nil, body: nil,
                    message: "Invalid response (not HTTP)", durationMs: durationMs
                )
                throw POTAError.uploadFailed("Invalid response")
            }

            let responseBody = String(data: data, encoding: .utf8) ?? "(binary data)"
            logUploadResponse(
                httpResponse, body: responseBody, data: data,
                parkReference: parkReference, durationMs: durationMs
            )
            await recordAttemptResult(
                attempt, httpResponse: httpResponse,
                responseBody: responseBody, durationMs: durationMs
            )

            return try handleUploadResponse(
                data: data, httpResponse: httpResponse,
                parkReference: parkReference, qsoCount: qsoCount
            )
        } catch let error as POTAError {
            throw error
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1_000)
            debugLog.error(
                "POTA upload network error for \(parkReference) (\(durationMs)ms): "
                    + "\(error.localizedDescription)",
                service: .pota
            )
            await recordAttemptFailure(
                attempt, statusCode: nil, body: nil,
                message: error.localizedDescription, durationMs: durationMs
            )
            throw POTAError.networkError(error)
        }
    }

    /// Log response details for debugging
    private func logUploadResponse(
        _ httpResponse: HTTPURLResponse, body: String, data: Data,
        parkReference: String, durationMs: Int
    ) {
        let debugLog = SyncDebugLog.shared
        let statusCode = httpResponse.statusCode
        let level: SyncDebugLog.LogEntry.Level =
            (200 ... 299).contains(statusCode) ? .info : .error
        debugLog.log(
            "POTA response for \(parkReference): HTTP \(statusCode) (\(durationMs)ms) "
                + "\(body.prefix(500))",
            level: level, service: .pota
        )
    }

    /// Record attempt as completed or failed based on status code
    private func recordAttemptResult(
        _ attempt: POTAUploadAttempt, httpResponse: HTTPURLResponse,
        responseBody: String, durationMs: Int
    ) async {
        if httpResponse.statusCode >= 200, httpResponse.statusCode < 300 {
            await MainActor.run {
                attempt.markCompleted(
                    httpStatusCode: httpResponse.statusCode,
                    responseBody: responseBody, durationMs: durationMs
                )
            }
        } else {
            await recordAttemptFailure(
                attempt, statusCode: httpResponse.statusCode,
                body: responseBody, message: nil, durationMs: durationMs
            )
        }
    }

    func recordAttemptFailure(
        _ attempt: POTAUploadAttempt, statusCode: Int?, body: String?,
        message: String?, durationMs: Int
    ) async {
        await MainActor.run {
            attempt.markFailed(
                httpStatusCode: statusCode, responseBody: body,
                errorMessage: message ?? "HTTP \(statusCode ?? 0)", durationMs: durationMs
            )
        }
    }

    /// Handle upload response
    func handleUploadResponse(
        data: Data,
        httpResponse: HTTPURLResponse,
        parkReference: String,
        qsoCount: Int
    ) throws -> POTAUploadResult {
        let debugLog = SyncDebugLog.shared

        switch httpResponse.statusCode {
        case 200 ... 299:
            return parseSuccessResponse(
                data: data, parkReference: parkReference, qsoCount: qsoCount
            )

        case 401:
            debugLog.error(
                "Upload failed: 401 Unauthorized - token may be expired", service: .pota
            )
            throw POTAError.notAuthenticated

        case 400 ... 499:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Client error"
            debugLog.error(
                "Upload failed: \(httpResponse.statusCode) - \(errorMessage)", service: .pota
            )
            throw POTAError.uploadFailed(errorMessage)

        default:
            debugLog.error(
                "Upload failed: \(httpResponse.statusCode) - Server error", service: .pota
            )
            throw POTAError.uploadFailed("Server error: \(httpResponse.statusCode)")
        }
    }

    private func parseSuccessResponse(data: Data, parkReference: String, qsoCount: Int)
        -> POTAUploadResult
    {
        let debugLog = SyncDebugLog.shared

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let responseStr = String(data: data, encoding: .utf8) ?? "(binary \(data.count) bytes)"
            debugLog.warning(
                "POTA response for \(parkReference) is not JSON "
                    + "- assuming \(qsoCount) accepted. Body: \(responseStr.prefix(500))",
                service: .pota
            )
            return POTAUploadResult(success: true, qsosAccepted: qsoCount, message: nil)
        }

        debugLog.debug(
            "POTA response JSON keys for \(parkReference): \(json.keys.sorted())",
            service: .pota
        )

        // Empty adif_files with HTTP 200 means the file is queued for async processing.
        // Log a note but treat as success - the server accepted the upload.
        if let adifFiles = json["adif_files"] as? [Any], adifFiles.isEmpty,
           json["qsosAccepted"] == nil
        {
            debugLog.info(
                "POTA returned empty adif_files for \(parkReference) "
                    + "- file queued for async processing. JSON: \(json)",
                service: .pota
            )
            return POTAUploadResult(
                success: true, qsosAccepted: qsoCount,
                message: "Upload accepted, awaiting processing"
            )
        }

        return parseAcceptedResponse(json: json, parkReference: parkReference, qsoCount: qsoCount)
    }

    private func parseAcceptedResponse(
        json: [String: Any], parkReference: String, qsoCount: Int
    ) -> POTAUploadResult {
        let debugLog = SyncDebugLog.shared
        let count = json["qsosAccepted"] as? Int
        let message = json["message"] as? String
        let accepted = count ?? qsoCount

        if count == nil {
            debugLog.warning(
                "POTA response for \(parkReference) has no 'qsosAccepted' key "
                    + "- assuming all \(qsoCount) accepted. JSON: \(json)",
                service: .pota
            )
        }
        if let message {
            debugLog.debug(
                "POTA response message for \(parkReference): \(message)", service: .pota
            )
        }
        if accepted == 0, qsoCount > 0 {
            debugLog.warning(
                "POTA reports 0 QSOs accepted for \(parkReference) "
                    + "but we sent \(qsoCount). JSON: \(json)",
                service: .pota
            )
        }

        debugLog.info(
            "Upload success: \(accepted) QSOs accepted for \(parkReference)"
                + (count == nil ? " (assumed)" : ""),
            service: .pota
        )
        return POTAUploadResult(success: true, qsosAccepted: accepted, message: message)
    }
}
