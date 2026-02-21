import CarrierWaveCore
import Foundation
import SwiftUI

// MARK: - CWTranscriptEntry

/// A single entry in the CW transcript
struct CWTranscriptEntry: Identifiable, Equatable, TranscriptEntryProtocol {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        isWordSpace: Bool = false,
        suggestionEngine: CWSuggestionEngine? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.isWordSpace = isWordSpace

        // Parse elements, then apply suggestions if engine is provided
        let baseElements = CallsignDetector.parseElements(from: text)
        if let engine = suggestionEngine, engine.suggestionsEnabled {
            elements = Self.applyWordSuggestions(to: baseElements, using: engine)
        } else {
            elements = baseElements
        }
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    let text: String
    let elements: [CWTextElement]
    let isWordSpace: Bool

    // MARK: Private

    /// Apply word suggestions to text elements
    private static func applyWordSuggestions(
        to elements: [CWTextElement],
        using engine: CWSuggestionEngine
    ) -> [CWTextElement] {
        elements.flatMap { element -> [CWTextElement] in
            guard case let .text(str) = element else {
                return [element]
            }

            // Split text into words, check each for suggestions
            let words = str.components(separatedBy: .whitespaces)
            var result: [CWTextElement] = []

            for (index, word) in words.enumerated() {
                if word.isEmpty {
                    continue
                }

                if let suggestion = engine.suggestCorrection(for: word) {
                    result.append(
                        .suggestion(
                            original: suggestion.originalWord,
                            suggested: suggestion.suggestedWord,
                            category: suggestion.category
                        )
                    )
                } else {
                    // Merge adjacent plain text
                    if case let .text(existing) = result.last {
                        result.removeLast()
                        result.append(.text(existing + " " + word))
                    } else {
                        result.append(.text(word))
                    }
                }

                // Add space between words (except last)
                if index < words.count - 1, !result.isEmpty {
                    if case let .text(existing) = result.last {
                        result.removeLast()
                        result.append(.text(existing + " "))
                    } else {
                        result.append(.text(" "))
                    }
                }
            }

            return result
        }
    }
}

// MARK: - CWTranscriptionState

/// Current state of the transcription service
enum CWTranscriptionState: Equatable {
    case idle
    case listening
    case error(String)
}

// MARK: - NoiseFloorQuality

/// Quality assessment of the noise floor
enum NoiseFloorQuality: String {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case unusable = "Too Noisy"

    // MARK: Internal

    var color: String {
        switch self {
        case .excellent: "green"
        case .good: "green"
        case .fair: "yellow"
        case .poor: "orange"
        case .unusable: "red"
        }
    }
}

// MARK: - CWTranscriptionService

/// Main service coordinating CW audio capture, signal processing, and decoding.
/// Publishes state updates for UI consumption.
@MainActor
@Observable
final class CWTranscriptionService {
    // MARK: - Published State

    /// Current transcription state
    var state: CWTranscriptionState = .idle

    /// Estimated WPM from decoder
    var estimatedWPM: Int = 20

    /// Decoded transcript entries
    var transcript: [CWTranscriptEntry] = []

    /// Current decoded text line being assembled
    var currentLine: String = ""

    /// Whether key is currently down (for UI indicator)
    var isKeyDown: Bool = false

    /// Peak amplitude for level meter (0.0-1.0)
    var peakAmplitude: Float = 0

    /// Whether still in calibration period
    var isCalibrating: Bool = true

    /// Recent envelope samples for waveform visualization
    var waveformSamples: [Float] = []

    /// Current noise floor level (0.0-1.0, normalized)
    var noiseFloor: Float = 0

    /// Current signal-to-noise ratio
    var signalToNoiseRatio: Float = 0

    /// Most recently detected callsign from transcript
    var detectedCallsign: DetectedCallsign?

    /// All callsigns detected in current session
    var detectedCallsigns: [String] = []

    /// Conversation tracker for chat-style display
    var conversationTracker = CWConversationTracker()

    /// Suggestion engine for word corrections
    var suggestionEngine = CWSuggestionEngine()

    /// Pre-amplifier enabled (boosts weak signals)
    var preAmpEnabled: Bool = false

    /// Detected tone frequency when using adaptive mode (nil if fixed frequency)
    var detectedFrequency: Double?

    /// Whether adaptive frequency detection is enabled
    var adaptiveFrequencyEnabled: Bool = true

    /// Minimum frequency for adaptive detection (Hz)
    var minFrequency: Double = 400

    /// Maximum frequency for adaptive detection (Hz)
    var maxFrequency: Double = 900

    /// Pre-amplifier gain multiplier when enabled
    let preAmpGain: Float = 10.0

    // MARK: - Private Properties

    var audioCapture: CWAudioCapture?
    var signalProcessor: (any CWSignalProcessorProtocol)?
    var morseDecoder: MorseDecoder?

    var captureTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?

    /// Maximum entries to keep in transcript
    let maxTranscriptEntries = 100

    /// Characters per line before wrapping
    let lineWrapLength = 40

    /// Track the last audio timestamp for timeout checking
    var lastAudioTimestamp: TimeInterval = 0

    /// The current conversation (convenience accessor)
    var conversation: CWConversation {
        conversationTracker.conversation
    }

    /// Whether currently listening
    var isListening: Bool {
        state == .listening
    }

    /// Whether noise floor is too high for reliable CW detection
    /// Noise is considered too high when it's above 0.3 (30% of dynamic range)
    var isNoiseTooHigh: Bool {
        noiseFloor > 0.3
    }

    /// Noise floor quality description for UI
    var noiseFloorQuality: NoiseFloorQuality {
        switch noiseFloor {
        case 0 ..< 0.1:
            .excellent
        case 0.1 ..< 0.2:
            .good
        case 0.2 ..< 0.3:
            .fair
        case 0.3 ..< 0.5:
            .poor
        default:
            .unusable
        }
    }

    /// Tone frequency for signal detection
    var toneFrequency: Double = 600 {
        didSet {
            Task {
                await signalProcessor?.setToneFrequency(toneFrequency)
            }
        }
    }

    // MARK: - Public API

    /// Start listening and transcribing CW
    func startListening() async {
        guard state != .listening else {
            return
        }

        do {
            // Create fresh instances
            audioCapture = CWAudioCapture()
            guard let capture = audioCapture else {
                return
            }

            // Signal processor will be created on first audio buffer
            // when we know the actual sample rate
            signalProcessor = nil

            morseDecoder = MorseDecoder(initialWPM: estimatedWPM)

            // Start capture
            let audioStream = try await capture.startCapture()
            state = .listening

            // Process audio in background task
            captureTask = Task {
                await processAudioStream(audioStream)
            }

            // Start timeout checker
            startTimeoutChecker()
        } catch let error as CWError {
            state = .error(error.localizedDescription)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Stop listening
    func stopListening() {
        captureTask?.cancel()
        captureTask = nil

        timeoutTask?.cancel()
        timeoutTask = nil

        Task {
            await audioCapture?.stopCapture()
            await signalProcessor?.reset()
            await morseDecoder?.reset()
        }

        audioCapture = nil
        state = .idle
        isKeyDown = false
        peakAmplitude = 0
        isCalibrating = true
        noiseFloor = 0
        signalToNoiseRatio = 0
        detectedFrequency = nil
    }

    /// Clear the transcript
    func clearTranscript() {
        transcript = []
        currentLine = ""
        detectedCallsign = nil
        detectedCallsigns = []
        conversationTracker.reset()
    }

    /// Copy transcript to clipboard
    func copyTranscript() -> String {
        let fullText = transcript.map { entry in
            entry.isWordSpace ? " " : entry.text
        }.joined()
        return (fullText + currentLine).trimmingCharacters(in: .whitespaces)
    }

    /// Manually set WPM (overrides adaptive)
    func setWPM(_ wpm: Int) {
        estimatedWPM = wpm
        Task {
            await morseDecoder?.setWPM(wpm)
        }
    }
}
