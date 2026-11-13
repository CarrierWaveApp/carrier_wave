import Foundation

// MARK: - SDRTranscriptWord

/// Atomic unit of time-aligned decoded CW text from the cw-swl server.
public struct SDRTranscriptWord: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        startOffset: TimeInterval,
        endOffset: TimeInterval,
        text: String,
        isCallsign: Bool,
        confidence: Float
    ) {
        self.id = id
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.text = text
        self.isCallsign = isCallsign
        self.confidence = confidence
    }

    // MARK: Public

    public let id: UUID
    /// Seconds from recording start
    public let startOffset: TimeInterval
    /// Seconds from recording start
    public let endOffset: TimeInterval
    /// Decoded text (e.g., "CQ", "DE", "W3ABC", "599")
    public let text: String
    /// Whether this word matches a callsign pattern
    public let isCallsign: Bool
    /// Decoder confidence 0.0-1.0
    public let confidence: Float
}

// MARK: - SDRTranscriptLine

/// A visual row in the transcript — a group of words spoken by one operator.
public struct SDRTranscriptLine: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        startOffset: TimeInterval,
        endOffset: TimeInterval,
        words: [SDRTranscriptWord],
        speakerCallsign: String?,
        operatorId: Int?,
        toneFreqHz: Float?
    ) {
        self.id = id
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.words = words
        self.speakerCallsign = speakerCallsign
        self.operatorId = operatorId
        self.toneFreqHz = toneFreqHz
    }

    // MARK: Public

    public let id: UUID
    /// First word's start offset
    public let startOffset: TimeInterval
    /// Last word's end offset
    public let endOffset: TimeInterval
    public let words: [SDRTranscriptWord]
    /// Attributed station callsign (nil when confidence is low)
    public let speakerCallsign: String?
    /// Frequency-based operator index (0, 1, 2, ...) for distinguishing transmitters
    public let operatorId: Int?
    /// Detected tone frequency in Hz for this line's operator
    public let toneFreqHz: Float?
}

// MARK: - DetectedQSORange

/// A QSO boundary detected from decoded CW text (CQ/exchange patterns).
public struct DetectedQSORange: Codable, Sendable {
    // MARK: Lifecycle

    public init(
        callsign: String,
        startOffset: TimeInterval,
        endOffset: TimeInterval,
        loggedQSOId: UUID?
    ) {
        self.callsign = callsign
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.loggedQSOId = loggedQSOId
    }

    // MARK: Public

    /// Callsign of the worked station
    public let callsign: String
    /// First CQ or callsign mention (seconds from recording start)
    public let startOffset: TimeInterval
    /// Final 73/SK/end of exchange (seconds from recording start)
    public let endOffset: TimeInterval
    /// Matched to a logged QSO if possible
    public let loggedQSOId: UUID?
}

// MARK: - SDRRecordingTranscript

/// Per-recording transcript envelope, cached as sidecar JSON.
public struct SDRRecordingTranscript: Codable, Sendable {
    // MARK: Lifecycle

    public init(
        recordingId: UUID,
        lines: [SDRTranscriptLine],
        detectedQSORanges: [DetectedQSORange],
        generatedAt: Date,
        decoderVersion: String,
        averageWPM: Int,
        averageConfidence: Float
    ) {
        self.recordingId = recordingId
        self.lines = lines
        self.detectedQSORanges = detectedQSORanges
        self.generatedAt = generatedAt
        self.decoderVersion = decoderVersion
        self.averageWPM = averageWPM
        self.averageConfidence = averageConfidence
    }

    // MARK: Public

    public let recordingId: UUID
    public let lines: [SDRTranscriptLine]
    public let detectedQSORanges: [DetectedQSORange]
    public let generatedAt: Date
    /// cw-swl version string
    public let decoderVersion: String
    public let averageWPM: Int
    public let averageConfidence: Float

    /// Sidecar JSON filename for a given session ID
    public static func sidecarFilename(sessionId: UUID) -> String {
        "\(sessionId.uuidString)-transcript.json"
    }

    /// Full sidecar JSON URL in the WebSDRRecordings directory
    public static func sidecarURL(sessionId: UUID) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            return nil
        }
        return docs
            .appendingPathComponent("WebSDRRecordings")
            .appendingPathComponent(sidecarFilename(sessionId: sessionId))
    }

    /// Load a cached transcript from disk, with noise lines filtered out
    public static func load(sessionId: UUID) -> SDRRecordingTranscript? {
        guard let url = sidecarURL(sessionId: sessionId),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder()
            .decode(SDRRecordingTranscript.self, from: data)
            .filteringNoise()
    }

    /// Save this transcript to the sidecar JSON file
    public func save(sessionId: UUID) throws {
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

    /// Return a copy with noise lines removed
    public func filteringNoise() -> SDRRecordingTranscript {
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
    /// Short prosigns and fragments that appear when decoding random noise.
    private static let noiseWords: Set<String> = [
        "HI", "AR", "EE", "ET", "TE", "TT", "EI", "IE", "IT", "TI",
        "II", "AE", "EA", "AI", "IA", "SE", "ES", "EN", "NE", "AN",
        "NA", "AA", "NN", "SK",
    ]

    /// Callsign pattern: 3-6 alphanumeric chars with at least one digit
    /// and at least one letter (simplified check).
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

    /// Returns true if a line is likely decoded noise rather than real CW.
    public static func isNoiseLine(_ line: SDRTranscriptLine) -> Bool {
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
