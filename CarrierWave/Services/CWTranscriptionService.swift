// swiftlint:disable file_length
import CarrierWaveCore
import Combine
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
final class CWTranscriptionService: ObservableObject {
    // MARK: Internal

    // MARK: - Published State

    /// Current transcription state
    @Published private(set) var state: CWTranscriptionState = .idle

    /// Estimated WPM from decoder
    @Published private(set) var estimatedWPM: Int = 20

    /// Decoded transcript entries
    @Published private(set) var transcript: [CWTranscriptEntry] = []

    /// Current decoded text line being assembled
    @Published private(set) var currentLine: String = ""

    /// Whether key is currently down (for UI indicator)
    @Published private(set) var isKeyDown: Bool = false

    /// Peak amplitude for level meter (0.0-1.0)
    @Published private(set) var peakAmplitude: Float = 0

    /// Whether still in calibration period
    @Published private(set) var isCalibrating: Bool = true

    /// Recent envelope samples for waveform visualization
    @Published private(set) var waveformSamples: [Float] = []

    /// Current noise floor level (0.0-1.0, normalized)
    @Published private(set) var noiseFloor: Float = 0

    /// Current signal-to-noise ratio
    @Published private(set) var signalToNoiseRatio: Float = 0

    /// Most recently detected callsign from transcript
    @Published private(set) var detectedCallsign: DetectedCallsign?

    /// All callsigns detected in current session
    @Published private(set) var detectedCallsigns: [String] = []

    /// Conversation tracker for chat-style display
    @Published private(set) var conversationTracker = CWConversationTracker()

    /// Suggestion engine for word corrections
    @Published var suggestionEngine = CWSuggestionEngine()

    /// Pre-amplifier enabled (boosts weak signals)
    @Published var preAmpEnabled: Bool = false

    /// Detected tone frequency when using adaptive mode (nil if fixed frequency)
    @Published private(set) var detectedFrequency: Double?

    /// Whether adaptive frequency detection is enabled
    @Published var adaptiveFrequencyEnabled: Bool = true

    /// Minimum frequency for adaptive detection (Hz)
    @Published var minFrequency: Double = 400

    /// Maximum frequency for adaptive detection (Hz)
    @Published var maxFrequency: Double = 900

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
    @Published var toneFrequency: Double = 600 {
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

    // MARK: Private

    /// Pre-amplifier gain multiplier when enabled
    private let preAmpGain: Float = 10.0

    // MARK: - Private Properties

    private var audioCapture: CWAudioCapture?
    private var signalProcessor: (any CWSignalProcessorProtocol)?
    private var morseDecoder: MorseDecoder?

    private var captureTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    /// Maximum entries to keep in transcript
    private let maxTranscriptEntries = 100

    /// Characters per line before wrapping
    private let lineWrapLength = 40

    /// Track the last audio timestamp for timeout checking
    private var lastAudioTimestamp: TimeInterval = 0

    // MARK: - Private Methods

    private func processAudioStream(_ stream: AsyncStream<CWAudioCapture.AudioBuffer>) async {
        var bufferCount = 0
        for await buffer in stream {
            bufferCount += 1
            if bufferCount.isMultiple(of: 100) {
                print("[CW] Processed \(bufferCount) audio buffers")
            }
            guard !Task.isCancelled else {
                break
            }

            await processAudioBuffer(buffer)
        }
    }

    private func processAudioBuffer(_ buffer: CWAudioCapture.AudioBuffer) async {
        // Create signal processor on first buffer using actual sample rate
        if signalProcessor == nil {
            createSignalProcessor(sampleRate: buffer.sampleRate)
        }

        guard let processor = signalProcessor else {
            return
        }

        // Apply pre-amp boost if enabled
        let samples = preAmpEnabled ? buffer.samples.map { $0 * preAmpGain } : buffer.samples
        let result = await processor.process(samples: samples, timestamp: buffer.timestamp)

        lastAudioTimestamp = buffer.timestamp
        updateUIState(from: result)

        // Process key events through decoder
        guard let decoder = morseDecoder else {
            return
        }
        for event in result.keyEvents {
            let outputs = await decoder.processKeyEvent(
                isKeyDown: event.isDown, timestamp: event.timestamp
            )
            await processDecoderOutputs(outputs)
        }

        // Update WPM
        let wpm = await decoder.estimatedWPM
        if estimatedWPM != wpm {
            estimatedWPM = wpm
        }
    }

    private func createSignalProcessor(sampleRate: Double) {
        if adaptiveFrequencyEnabled {
            print(
                "[CW] Creating adaptive signal processor: \(Int(minFrequency))-\(Int(maxFrequency)) Hz"
            )
            signalProcessor = GoertzelSignalProcessor(
                sampleRate: sampleRate,
                minFrequency: minFrequency,
                maxFrequency: maxFrequency,
                frequencyStep: 50
            )
        } else {
            print("[CW] Creating fixed signal processor at \(Int(toneFrequency)) Hz")
            signalProcessor = GoertzelSignalProcessor(
                sampleRate: sampleRate, toneFrequency: toneFrequency
            )
        }
    }

    private func updateUIState(from result: CWSignalResult) {
        isKeyDown = result.isKeyDown
        peakAmplitude = result.peakAmplitude
        waveformSamples = result.envelopeSamples
        isCalibrating = result.isCalibrating
        noiseFloor = result.noiseFloor
        signalToNoiseRatio = result.signalToNoiseRatio
        detectedFrequency = result.detectedFrequency
    }

    private func processDecoderOutputs(_ outputs: [DecodedOutput]) async {
        for output in outputs {
            switch output {
            case let .character(char):
                print("[CW] Service received character: '\(char)'")
                await MainActor.run {
                    appendCharacter(char)
                }
            case .wordSpace:
                print("[CW] Service received word space")
                await MainActor.run {
                    appendWordSpace()
                }
            case .element:
                // Raw elements are for debugging, skip for now
                break
            }
        }
    }

    private func appendCharacter(_ char: String) {
        currentLine += char
        print("[CW] currentLine is now: '\(currentLine)'")

        // Check for line wrap
        if currentLine.count >= lineWrapLength {
            flushCurrentLine()
        }
    }

    private func appendWordSpace() {
        // Only add space if there's content
        if !currentLine.isEmpty {
            currentLine += " "
        }
    }

    private func flushCurrentLine() {
        guard !currentLine.isEmpty else {
            return
        }

        // Find last space for word boundary
        let text: String
        let remainder: String

        if let lastSpace = currentLine.lastIndex(of: " ") {
            // Include trailing space to preserve word boundary
            text = String(currentLine[...lastSpace])
            remainder = String(currentLine[currentLine.index(after: lastSpace)...])
        } else {
            text = currentLine
            remainder = ""
        }

        let entry = CWTranscriptEntry(text: text, suggestionEngine: suggestionEngine)
        transcript.append(entry)
        currentLine = remainder

        // Forward to conversation tracker with current frequency
        conversationTracker.processEntry(entry, frequency: detectedFrequency)

        // Trim old entries
        if transcript.count > maxTranscriptEntries {
            transcript.removeFirst(transcript.count - maxTranscriptEntries)
        }

        // Update detected callsigns
        updateDetectedCallsigns()
    }

    private func updateDetectedCallsigns() {
        // Extract all callsigns from current transcript
        let allText = transcript.map(\.text).joined(separator: " ") + " " + currentLine
        let newCallsigns = CallsignDetector.extractCallsigns(from: allText)

        // Update unique callsigns list
        for callsign in newCallsigns where !detectedCallsigns.contains(callsign) {
            detectedCallsigns.append(callsign)
        }

        // Update primary detected callsign
        if let primary = CallsignDetector.detectPrimaryCallsign(from: transcript) {
            detectedCallsign = primary
        }
    }

    private func startTimeoutChecker() {
        timeoutTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                guard let decoder = morseDecoder else {
                    continue
                }
                // Use audio timestamp + elapsed time for consistent time reference
                // Add 0.1 seconds for each check interval
                let checkTime = lastAudioTimestamp + 0.1
                let outputs = await decoder.checkTimeout(currentTime: checkTime)
                await processDecoderOutputs(outputs)
            }
        }
    }
}
