import CarrierWaveCore
import Foundation

// MARK: - MorseElement

/// A decoded morse element (dit, dah, or gap)
enum MorseElement: Equatable, Sendable {
    case dit
    case dah
    case elementGap // Gap within character
    case charGap // Gap between characters
    case wordGap // Gap between words

    // MARK: Internal

    nonisolated var symbol: String {
        switch self {
        case .dit: "."
        case .dah: "-"
        case .elementGap: ""
        case .charGap: " "
        case .wordGap: "  "
        }
    }

    nonisolated static func == (lhs: MorseElement, rhs: MorseElement) -> Bool {
        switch (lhs, rhs) {
        case (.dit, .dit),
             (.dah, .dah),
             (.elementGap, .elementGap),
             (.charGap, .charGap),
             (.wordGap, .wordGap):
            true
        default:
            false
        }
    }
}

// MARK: - DecodedOutput

/// Output from the morse decoder
enum DecodedOutput: Equatable, Sendable {
    /// A character was decoded
    case character(String)

    /// A word gap was detected (space)
    case wordSpace

    /// Raw element for debugging/visualization
    case element(MorseElement)
}

// MARK: - MorseDecoder

/// Decodes morse code from key timing events.
/// Uses adaptive timing to estimate WPM and classify elements.
actor MorseDecoder {
    // MARK: Lifecycle

    // MARK: - Initialization

    init(initialWPM: Int = 20) {
        estimatedWPM = initialWPM
        unitDuration = MorseCode.Timing.unitDuration(forWPM: initialWPM)
    }

    // MARK: Internal

    // MARK: - State

    /// Current estimated WPM
    private(set) var estimatedWPM: Int

    // MARK: - Public API

    /// Process a key state change event
    /// - Parameters:
    ///   - isKeyDown: Whether the key is now down (tone on)
    ///   - timestamp: Time of the event
    /// - Returns: Any decoded output from this event
    func processKeyEvent(isKeyDown: Bool, timestamp: TimeInterval) -> [DecodedOutput] {
        var outputs: [DecodedOutput] = []

        // Initialize on first event
        if lastStateChange == 0 {
            lastStateChange = timestamp
            lastKeyDown = isKeyDown
            lastElementTime = timestamp
            return outputs
        }

        let duration = timestamp - lastStateChange

        if lastKeyDown, !isKeyDown {
            // Key was down, now up: classify the tone duration
            // Filter out noise spikes that are too short to be valid morse
            if duration < minimumToneDuration {
                let durationMs = String(format: "%.1f", duration * 1_000)
                let minMs = String(format: "%.1f", minimumToneDuration * 1_000)
                print("[CW] Ignoring noise spike: \(durationMs)ms (min: \(minMs)ms)")
                lastKeyDown = isKeyDown
                lastStateChange = timestamp
                return outputs
            }

            let element = classifyToneDuration(duration)
            outputs.append(.element(element))

            // Add to pattern
            currentPattern += element.symbol
            let elementName = element == .dit ? "DIT" : "DAH"
            let durationMs = String(format: "%.0f", duration * 1_000)
            print("[CW] Tone ended: \(elementName) (\(durationMs)ms) - pattern: \(currentPattern)")

            // Update WPM estimate from this element
            updateWPMEstimate(duration: duration, element: element)
            lastElementTime = timestamp
        } else if !lastKeyDown, isKeyDown {
            // Key was up, now down: classify the gap duration
            // Filter out micro-gaps that are false triggers
            if duration < minimumGapDuration {
                let durationMs = String(format: "%.1f", duration * 1_000)
                let minMs = String(format: "%.1f", minimumGapDuration * 1_000)
                print("[CW] Ignoring micro-gap: \(durationMs)ms (min: \(minMs)ms)")
                // Don't update state - treat as if key was still down
                return outputs
            }

            let gapOutput = processGap(duration: duration, timestamp: timestamp)
            outputs.append(contentsOf: gapOutput)
            print(
                "[CW] Gap ended: \(String(format: "%.0f", duration * 1_000))ms - outputs: \(gapOutput)"
            )

            lastElementTime = timestamp
        }

        lastKeyDown = isKeyDown
        lastStateChange = timestamp

        return outputs
    }

    /// Check for timeout and flush any pending character
    /// Call this periodically (e.g., every 100ms) when no key events
    /// - Parameter currentTime: Current timestamp
    /// - Returns: Any decoded output from timeout
    func checkTimeout(currentTime: TimeInterval) -> [DecodedOutput] {
        guard !currentPattern.isEmpty else {
            return []
        }

        let silenceDuration = currentTime - lastElementTime
        let timeoutDuration = unitDuration * charTimeoutUnits

        if silenceDuration > timeoutDuration {
            return flushCurrentCharacter()
        }

        return []
    }

    /// Reset decoder state (call when starting new session)
    func reset() {
        currentPattern = ""
        lastKeyDown = false
        lastStateChange = 0
        lastElementTime = 0
        recentDurations = []
        // Keep current WPM estimate
    }

    /// Reset decoder including WPM estimate
    func fullReset(wpm: Int? = nil) {
        reset()
        estimatedWPM = wpm ?? initialWPM
        unitDuration = MorseCode.Timing.unitDuration(forWPM: estimatedWPM)
        manualWPMMode = false // Re-enable adaptive estimation on full reset
    }

    /// Manually set WPM (disables adaptive estimation)
    func setWPM(_ wpm: Int) {
        estimatedWPM = max(minWPM, min(maxWPM, wpm))
        unitDuration = MorseCode.Timing.unitDuration(forWPM: estimatedWPM)
        manualWPMMode = true
        recentDurations = [] // Clear stale timing data
        let unitMs = String(format: "%.1f", unitDuration * 1_000)
        print("[CW] Manual WPM set to \(estimatedWPM), unit duration: \(unitMs)ms")
    }

    /// Enable adaptive WPM estimation (re-enables after manual set)
    func enableAdaptiveWPM() {
        manualWPMMode = false
        recentDurations = []
    }

    // MARK: Private

    // MARK: - Configuration

    /// Minimum WPM to consider (prevents unreasonably slow detection)
    private let minWPM: Int = 5

    /// Maximum WPM to consider (prevents unreasonably fast detection)
    private let maxWPM: Int = 60

    /// Initial WPM estimate
    private let initialWPM: Int = 20

    /// Tolerance factor for timing classification (allows for human variation)
    private let timingTolerance: Double = 0.5

    /// Minimum tone duration to consider valid (filters noise spikes)
    /// At 40 WPM, a dit is 30ms, so 25ms is a reasonable minimum
    private let minimumToneDuration: TimeInterval = 0.025

    /// Minimum gap duration to consider valid (filters false key-up triggers)
    /// At 40 WPM, element gap is 30ms, so 20ms is a reasonable minimum
    private let minimumGapDuration: TimeInterval = 0.020

    /// Minimum samples needed before adapting WPM
    private let minSamplesForAdaptation: Int = 3

    /// Estimated unit duration in seconds
    private var unitDuration: TimeInterval

    /// When true, adaptive WPM estimation is disabled (user set WPM manually)
    private var manualWPMMode: Bool = false

    /// Current morse pattern being assembled
    private var currentPattern: String = ""

    /// Last key state
    private var lastKeyDown: Bool = false

    /// Timestamp of last state change
    private var lastStateChange: TimeInterval = 0

    /// Recent element durations for WPM estimation (key-down only)
    private var recentDurations: [TimeInterval] = []

    /// Maximum durations to keep for averaging (smaller = more responsive)
    private let maxDurationSamples: Int = 10

    /// Time since last element (for detecting timeouts)
    private var lastElementTime: TimeInterval = 0

    /// Timeout for completing a character (in unit durations)
    private let charTimeoutUnits: Double = 5.0

    // MARK: - Private Methods

    /// Classify a tone (key-down) duration as dit or dah
    private func classifyToneDuration(_ duration: TimeInterval) -> MorseElement {
        // Threshold between dit and dah is 2 units (midpoint of 1 and 3)
        let threshold = unitDuration * 2.0

        // Apply tolerance for edge cases
        let toleranceRange = unitDuration * timingTolerance

        if duration < threshold - toleranceRange {
            return .dit
        } else if duration > threshold + toleranceRange {
            return .dah
        } else {
            // In the fuzzy zone - use ratio to decide
            // Dit = 1 unit, Dah = 3 units
            let ditDistance = abs(duration - unitDuration)
            let dahDistance = abs(duration - unitDuration * 3)
            return ditDistance < dahDistance ? .dit : .dah
        }
    }

    /// Process a gap (key-up) duration
    private func processGap(duration: TimeInterval, timestamp _: TimeInterval) -> [DecodedOutput] {
        var outputs: [DecodedOutput] = []

        // Gap thresholds:
        // Element gap: 1 unit (within character)
        // Character gap: 3 units (between characters)
        // Word gap: 7 units (between words)
        //
        // Use adaptive thresholds based on WPM, but with absolute limits to prevent
        // runaway feedback loops where wrong WPM causes wrong gap classification
        // which causes even more wrong WPM.

        let charGapThreshold = unitDuration * 2.0 // Lowered from 2.5 to be more aggressive
        let wordGapThreshold = unitDuration * 5.0 // Lowered from 5.5

        // Absolute minimum thresholds to prevent feedback loops
        // At any reasonable WPM (5-40), character gaps should be at least 120ms
        // and word gaps at least 280ms
        let minCharGapThreshold: TimeInterval = 0.120
        let minWordGapThreshold: TimeInterval = 0.280

        let effectiveCharGap = max(charGapThreshold, minCharGapThreshold)
        let effectiveWordGap = max(wordGapThreshold, minWordGapThreshold)

        // Also use pattern length as a heuristic - if we've accumulated many elements,
        // we're probably missing character boundaries
        let patternTooLong = currentPattern.count >= 6

        if duration < effectiveCharGap, !patternTooLong {
            // Element gap - within character, no action needed
            outputs.append(.element(.elementGap))
        } else if duration < effectiveWordGap {
            // Character gap - decode current pattern
            outputs.append(.element(.charGap))
            outputs.append(contentsOf: flushCurrentCharacter())
        } else {
            // Word gap - decode current pattern and add space
            outputs.append(.element(.wordGap))
            outputs.append(contentsOf: flushCurrentCharacter())
            outputs.append(.wordSpace)
        }

        return outputs
    }

    /// Decode and clear the current pattern
    private func flushCurrentCharacter() -> [DecodedOutput] {
        guard !currentPattern.isEmpty else {
            return []
        }

        var outputs: [DecodedOutput] = []

        if let decoded = MorseCode.decode(currentPattern) {
            print("[CW] Decoded: '\(currentPattern)' -> '\(decoded)'")
            outputs.append(.character(decoded))
        } else {
            // Unknown pattern - output as-is with marker
            print("[CW] Unknown pattern: '\(currentPattern)'")
            outputs.append(.character("[\(currentPattern)]"))
        }

        currentPattern = ""
        return outputs
    }

    /// Update WPM estimate based on a classified element
    private func updateWPMEstimate(duration: TimeInterval, element: MorseElement) {
        // Skip adaptation when user has manually set WPM
        guard !manualWPMMode else {
            print("[CW] Skipping WPM adaptation - manual mode enabled")
            return
        }

        // Only use dits and dahs for estimation
        guard element == .dit || element == .dah else {
            return
        }

        // Calculate what the unit duration would be for this element
        let estimatedUnit: TimeInterval =
            if element == .dit {
                duration / MorseCode.Timing.ditUnits
            } else {
                duration / MorseCode.Timing.dahUnits
            }

        // Sanity check: reject unreasonable unit durations
        let minUnit = MorseCode.Timing.unitDuration(forWPM: maxWPM)
        let maxUnit = MorseCode.Timing.unitDuration(forWPM: minWPM)
        guard estimatedUnit >= minUnit, estimatedUnit <= maxUnit else {
            print(
                "[CW] Rejecting unreasonable unit estimate: \(String(format: "%.1f", estimatedUnit * 1_000))ms"
            )
            return
        }

        // Add to recent samples
        recentDurations.append(estimatedUnit)
        if recentDurations.count > maxDurationSamples {
            recentDurations.removeFirst()
        }

        // Need enough samples before adapting
        guard recentDurations.count >= minSamplesForAdaptation else {
            return
        }

        // Use median for robustness against outliers
        let sorted = recentDurations.sorted()
        let medianUnit = sorted[sorted.count / 2]

        // Detect speed jumps - if the new median differs significantly from current,
        // use a higher smoothing factor to catch up faster
        let speedRatio = medianUnit / unitDuration
        let isSpeedJump = speedRatio < 0.75 || speedRatio > 1.33 // ~25% speed change

        // Use higher smoothing (50%) for speed jumps, moderate (40%) otherwise
        // This prioritizes responsiveness over stability
        let smoothingFactor = isSpeedJump ? 0.50 : 0.40
        unitDuration = unitDuration * (1 - smoothingFactor) + medianUnit * smoothingFactor

        if isSpeedJump {
            print(
                "[CW] Speed jump detected (ratio: \(String(format: "%.2f", speedRatio))), using aggressive smoothing"
            )
        }

        // Clamp to valid range
        unitDuration = max(minUnit, min(maxUnit, unitDuration))

        // Update WPM
        let oldWPM = estimatedWPM
        estimatedWPM = MorseCode.Timing.wpm(fromUnitDuration: unitDuration)
        if estimatedWPM != oldWPM {
            print("[CW] Adaptive WPM updated: \(oldWPM) -> \(estimatedWPM)")
        }
    }
}

// MARK: - MorseDecoderDelegate

/// Protocol for receiving decoded morse output
protocol MorseDecoderDelegate: AnyObject {
    /// Called when a character is decoded
    func morseDecoder(_ decoder: MorseDecoder, didDecode character: String)

    /// Called when a word space is detected
    func morseDecoderDidDetectWordSpace(_ decoder: MorseDecoder)

    /// Called when WPM estimate changes
    func morseDecoder(_ decoder: MorseDecoder, didUpdateWPM wpm: Int)
}
