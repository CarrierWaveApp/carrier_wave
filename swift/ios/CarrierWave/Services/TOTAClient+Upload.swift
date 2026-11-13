// TOTA ADIF upload (multipart/form-data).
//
// POST https://icneuzxitdqtofutxbla.supabase.co/functions/v1/activations
//   Auth: x-api-key (required).
//   Body: multipart/form-data with the ADIF payload in a field named `adif`.
//   Server parses ADIF 3.x and computes points server-side.

import UIKit

extension TOTAClient {
    /// Upload an ADIF file representing one or more TOTA activations.
    /// - Parameters:
    ///   - adifContent: Standard ADIF 3.x text. The server expects the file
    ///     contents directly (no extra wrapping).
    ///   - filename: Suggested filename for the multipart part. Defaults to a
    ///     timestamped name; the server doesn't currently key off this value.
    @discardableResult
    func uploadADIF(
        _ adifContent: String,
        filename: String? = nil
    ) async throws -> TOTAActivationResponse {
        var urlRequest = try makeRequest(
            path: "/activations",
            method: "POST",
            requireAuth: true
        )

        let boundary = "tota-\(UUID().uuidString)"
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let resolvedFilename = filename ?? Self.defaultFilename()
        urlRequest.httpBody = Self.makeMultipartBody(
            boundary: boundary,
            fieldName: "adif",
            filename: resolvedFilename,
            contents: adifContent
        )

        let data = try await executeRequest(urlRequest)
        return try Self.decodeActivationResponse(data)
    }

    // MARK: Internal helpers

    static func makeMultipartBody(
        boundary: String,
        fieldName: String,
        filename: String,
        contents: String
    ) -> Data {
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString(
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n"
        )
        body.appendString("Content-Type: text/plain\r\n\r\n")
        body.appendString(contents)
        body.appendString("\r\n--\(boundary)--\r\n")
        return body
    }

    static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "tota-\(formatter.string(from: Date())).adi"
    }
}

// MARK: - Data multipart helper

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
