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

// MARK: - POTAClient Upload Methods

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

        // Filter QSOs for this park, excluding metadata modes (WEATHER, SOLAR, NOTE)
        // Uses hasOverlap to support multi-park/two-fer references (e.g., "US-1044, US-3791")
        let parkQSOs = qsos.filter {
            guard let ref = $0.parkReference else { return false }
            return ParkReference.hasOverlap(ref, normalizedParkRef)
                && !Self.metadataModes.contains($0.mode.uppercased())
        }
        guard !parkQSOs.isEmpty else {
            debugLog.info("No QSOs to upload for park \(normalizedParkRef)", service: .pota)
            return nil
        }

        let callsign = parkQSOs.first?.myCallsign ?? "UNKNOWN"
        let location = deriveLocation(
            parkReference: normalizedParkRef, grid: parkQSOs.first?.myGrid
        )
        let adifContent = generateADIF(for: parkQSOs, parkReference: normalizedParkRef)
        let filename = buildFilename(
            callsign: callsign, parkReference: normalizedParkRef, qsos: parkQSOs
        )
        let formFields = POTAFormFields(
            parkReference: normalizedParkRef, location: location, callsign: callsign
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

    func deriveLocation(parkReference: String, grid: String?) -> String {
        let parkPrefix = parkReference.split(separator: "-").first.map(String.init) ?? "US"
        let derivedState = grid.flatMap { Self.gridToUSState($0) }
        if parkPrefix == "US" || parkPrefix == "K", let state = derivedState {
            return "US-\(state)"
        }
        return parkPrefix
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
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1_000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await recordAttemptFailure(
                    attempt, statusCode: nil, body: nil,
                    message: "Invalid response (not HTTP)", durationMs: durationMs
                )
                throw POTAError.uploadFailed("Invalid response")
            }

            let responseBody = String(data: data, encoding: .utf8) ?? "(binary data)"

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

            return try handleUploadResponse(
                data: data, httpResponse: httpResponse,
                parkReference: parkReference, qsoCount: qsoCount
            )
        } catch let error as POTAError {
            throw error
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1_000)
            await recordAttemptFailure(
                attempt, statusCode: nil, body: nil,
                message: error.localizedDescription, durationMs: durationMs
            )
            throw POTAError.networkError(error)
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
        let responseBody = String(data: data, encoding: .utf8) ?? "(binary data)"
        debugLog.debug(
            "Response \(httpResponse.statusCode): \(responseBody.prefix(500))", service: .pota
        )

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
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let count = json["qsosAccepted"] as? Int ?? qsoCount
            let message = json["message"] as? String
            debugLog.info(
                "Upload success: \(count) QSOs accepted for \(parkReference)", service: .pota
            )
            return POTAUploadResult(success: true, qsosAccepted: count, message: message)
        }
        debugLog.info(
            "Upload success: \(qsoCount) QSOs for \(parkReference) (no count in response)",
            service: .pota
        )
        return POTAUploadResult(success: true, qsosAccepted: qsoCount, message: nil)
    }
}
