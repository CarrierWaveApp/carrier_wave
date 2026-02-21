import Foundation

// MARK: - SDRTranscriptWord

/// Atomic unit of time-aligned decoded CW text from the cw-swl server.
struct SDRTranscriptWord: Codable, Sendable, Identifiable {
    let id: UUID
    /// Seconds from recording start
    let startOffset: TimeInterval
    /// Seconds from recording start
    let endOffset: TimeInterval
    /// Decoded text (e.g., "CQ", "DE", "W3ABC", "599")
    let text: String
    /// Whether this word matches a callsign pattern
    let isCallsign: Bool
    /// Decoder confidence 0.0-1.0
    let confidence: Float
}

// MARK: - SDRTranscriptLine

/// A visual row in the transcript — a group of words spoken by one operator.
struct SDRTranscriptLine: Codable, Sendable, Identifiable {
    let id: UUID
    /// First word's start offset
    let startOffset: TimeInterval
    /// Last word's end offset
    let endOffset: TimeInterval
    let words: [SDRTranscriptWord]
    /// Attributed station callsign (nil when confidence is low)
    let speakerCallsign: String?
}

// MARK: - DetectedQSORange

/// A QSO boundary detected from decoded CW text (CQ/exchange patterns).
struct DetectedQSORange: Codable, Sendable {
    /// Callsign of the worked station
    let callsign: String
    /// First CQ or callsign mention (seconds from recording start)
    let startOffset: TimeInterval
    /// Final 73/SK/end of exchange (seconds from recording start)
    let endOffset: TimeInterval
    /// Matched to a logged QSO if possible
    let loggedQSOId: UUID?
}

// MARK: - SDRRecordingTranscript

/// Per-recording transcript envelope, cached as sidecar JSON.
struct SDRRecordingTranscript: Codable, Sendable {
    let recordingId: UUID
    let lines: [SDRTranscriptLine]
    let detectedQSORanges: [DetectedQSORange]
    let generatedAt: Date
    /// cw-swl version string
    let decoderVersion: String
    let averageWPM: Int
    let averageConfidence: Float

    /// Sidecar JSON filename for a given session ID
    static func sidecarFilename(sessionId: UUID) -> String {
        "\(sessionId.uuidString)-transcript.json"
    }

    /// Full sidecar JSON URL in the WebSDRRecordings directory
    static func sidecarURL(sessionId: UUID) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            return nil
        }
        return docs
            .appendingPathComponent("WebSDRRecordings")
            .appendingPathComponent(sidecarFilename(sessionId: sessionId))
    }

    /// Load a cached transcript from disk
    static func load(sessionId: UUID) -> SDRRecordingTranscript? {
        guard let url = sidecarURL(sessionId: sessionId),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(SDRRecordingTranscript.self, from: data)
    }

    /// Save this transcript to the sidecar JSON file
    func save(sessionId: UUID) throws {
        guard let url = SDRRecordingTranscript.sidecarURL(sessionId: sessionId) else {
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
