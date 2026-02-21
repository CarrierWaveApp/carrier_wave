import Foundation

// MARK: - TranscriptionStatus

/// Status of an async transcription job on the cw-swl server
enum TranscriptionStatus: Sendable {
    case inProgress(progress: Float)
    case completed(SDRRecordingTranscript)
    case failed(String)
}

// MARK: - CWSWLError

enum CWSWLError: Error, LocalizedError {
    case noServerConfigured
    case invalidURL
    case uploadFailed(String)
    case transcriptionFailed(String)
    case invalidResponse
    case serverUnreachable

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noServerConfigured:
            "No cw-swl server configured. Set the URL in Settings > Developer."
        case .invalidURL:
            "Invalid cw-swl server URL"
        case let .uploadFailed(msg):
            "Upload failed: \(msg)"
        case let .transcriptionFailed(msg):
            "Transcription failed: \(msg)"
        case .invalidResponse:
            "Invalid response from cw-swl server"
        case .serverUnreachable:
            "Cannot reach cw-swl server. Check the URL in Settings > Developer."
        }
    }
}

// MARK: - CWSWLClient

/// Actor for communicating with the cw-swl CW transcription server.
/// Handles audio upload, async transcription, and structured transcript retrieval.
actor CWSWLClient {
    // MARK: Internal

    /// Upload a local recording file for transcription
    func uploadRecording(fileURL: URL) async throws -> UUID {
        let base = try baseURL()
        let url = base.appendingPathComponent("api/v1/recordings/upload")

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.timeoutInterval = 120

        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL)

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; ")
        body.append("filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")

        request.httpBody = body

        let (responseData, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201
        else {
            throw CWSWLError.uploadFailed("Server returned non-201 status")
        }

        let decoded = try JSONDecoder().decode(
            UploadResponse.self, from: responseData
        )
        return decoded.id
    }

    /// Start transcription of an uploaded recording
    func startTranscription(recordingId: UUID) async throws -> UUID {
        let base = try baseURL()
        let url = base.appendingPathComponent("api/v1/transcriptions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TranscriptionRequest(recordingId: recordingId)
        )

        let (data, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202
        else {
            throw CWSWLError.transcriptionFailed("Server returned non-202 status")
        }

        let decoded = try JSONDecoder().decode(
            TranscriptionJobResponse.self, from: data
        )
        return decoded.id
    }

    /// Poll transcription status
    func transcriptionStatus(id: UUID) async throws -> TranscriptionStatus {
        let base = try baseURL()
        let url = base.appendingPathComponent("api/v1/transcriptions/\(id)")

        let request = URLRequest(url: url)
        let (data, _) = try await performRequest(request)

        let decoded = try JSONDecoder().decode(
            TranscriptionStatusResponse.self, from: data
        )

        switch decoded.status {
        case "in_progress":
            return .inProgress(progress: decoded.progress ?? 0)
        case "completed":
            guard let transcript = decoded.transcript else {
                throw CWSWLError.invalidResponse
            }
            return .completed(transcript)
        case "failed":
            return .failed(decoded.errorMessage ?? "Unknown error")
        default:
            throw CWSWLError.invalidResponse
        }
    }

    /// Convenience: upload + transcribe + poll until complete
    func transcribe(
        fileURL: URL,
        progress: @Sendable @escaping (Float) -> Void
    ) async throws -> SDRRecordingTranscript {
        let recordingId = try await uploadRecording(fileURL: fileURL)
        progress(0.05)

        let jobId = try await startTranscription(recordingId: recordingId)
        progress(0.1)

        // Poll until complete
        while true {
            try await Task.sleep(for: .seconds(2))
            let status = try await transcriptionStatus(id: jobId)

            switch status {
            case let .inProgress(serverProgress):
                progress(0.1 + serverProgress * 0.9)
            case let .completed(transcript):
                progress(1.0)
                return transcript
            case let .failed(message):
                throw CWSWLError.transcriptionFailed(message)
            }
        }
    }

    // MARK: Private

    private let session = URLSession.shared

    private func baseURL() throws -> URL {
        let urlString = UserDefaults.standard.string(forKey: "cwswlServerURL") ?? ""
        guard !urlString.isEmpty else {
            throw CWSWLError.noServerConfigured
        }
        guard let url = URL(string: urlString) else {
            throw CWSWLError.invalidURL
        }
        return url
    }

    private func performRequest(
        _ request: URLRequest
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError
            where error.code == .cannotConnectToHost
            || error.code == .timedOut
            || error.code == .cannotFindHost
        {
            throw CWSWLError.serverUnreachable
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "caf": "audio/x-caf"
        case "m4a": "audio/mp4"
        case "wav": "audio/wav"
        default: "application/octet-stream"
        }
    }
}

// MARK: - UploadResponse

private struct UploadResponse: nonisolated Decodable, Sendable {
    let id: UUID
}

// MARK: - TranscriptionRequest

private struct TranscriptionRequest: nonisolated Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case recordingId = "recording_id"
    }

    let recordingId: UUID
}

// MARK: - TranscriptionJobResponse

private struct TranscriptionJobResponse: nonisolated Decodable, Sendable {
    let id: UUID
}

// MARK: - TranscriptionStatusResponse

private struct TranscriptionStatusResponse: nonisolated Decodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case status
        case progress
        case transcript
        case errorMessage = "error_message"
    }

    let status: String
    let progress: Float?
    let transcript: SDRRecordingTranscript?
    let errorMessage: String?
}

// MARK: - Data Extension

nonisolated private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
