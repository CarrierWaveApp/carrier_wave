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
    /// Frequency-based operator index (0, 1, 2, ...) for distinguishing transmitters
    let operatorId: Int?
    /// Detected tone frequency in Hz for this line's operator
    let toneFreqHz: Float?
}

// MARK: - DetectedQSORange

/// A QSO boundary detected from decoded CW text (CQ/exchange patterns).
struct DetectedQSORange: Codable, Sendable {
    let callsign: String
    let startOffset: TimeInterval
    let endOffset: TimeInterval
    let loggedQSOId: UUID?
}

// MARK: - SDRRecordingTranscript

/// Per-recording transcript envelope, cached as sidecar JSON.
struct SDRRecordingTranscript: Codable, Sendable {
    let recordingId: UUID
    let lines: [SDRTranscriptLine]
    let detectedQSORanges: [DetectedQSORange]
    let generatedAt: Date
    let decoderVersion: String
    let averageWPM: Int
    let averageConfidence: Float

    static func sidecarFilename(sessionId: UUID) -> String {
        "\(sessionId.uuidString)-transcript.json"
    }

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

    static func load(sessionId: UUID) -> SDRRecordingTranscript? {
        guard let url = sidecarURL(sessionId: sessionId),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder()
            .decode(SDRRecordingTranscript.self, from: data)
            .filteringNoise()
    }

    func save(sessionId: UUID) throws {
        guard let url = SDRRecordingTranscript.sidecarURL(sessionId: sessionId) else {
            return
        }
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    func filteringNoise() -> SDRRecordingTranscript {
        let filtered = lines.filter { !Self.isNoiseLine($0) }
        return SDRRecordingTranscript(
            recordingId: recordingId,
            lines: filtered,
            detectedQSORanges: detectedQSORanges,
            generatedAt: generatedAt,
            decoderVersion: decoderVersion,
            averageWPM: averageWPM,
            averageConfidence: averageConfidence
        )
    }
}

// MARK: - Noise Detection

extension SDRRecordingTranscript {
    private static let noiseWords: Set<String> = [
        "HI", "AR", "EE", "ET", "TE", "TT", "EI", "IE", "IT", "TI",
        "II", "AE", "EA", "AI", "IA", "SE", "ES", "EN", "NE", "AN",
        "NA", "AA", "NN", "SK",
    ]

    private static func looksLikeCallsign(_ text: String) -> Bool {
        let upper = text.uppercased()
        guard (3 ... 6).contains(upper.count),
              upper.allSatisfy(\.isASCII),
              upper.allSatisfy({ $0.isLetter || $0.isNumber }),
              upper.contains(where: \.isNumber),
              upper.contains(where: \.isLetter)
        else {
            return false
        }
        return true
    }

    static func isNoiseLine(_ line: SDRTranscriptLine) -> Bool {
        guard !line.words.isEmpty else {
            return true
        }
        let hasCallsign = line.words.contains { looksLikeCallsign($0.text) }
        if hasCallsign {
            return false
        }
        return line.words.allSatisfy {
            noiseWords.contains($0.text.uppercased())
        }
    }
}
