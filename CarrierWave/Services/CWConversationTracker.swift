import CarrierWaveData
import Foundation

// MARK: - CWConversationTracker

/// Tracks CW conversation turns based on frequency changes and prosign analysis.
/// Groups decoded text into messages attributed to different stations.
@MainActor
@Observable
final class CWConversationTracker {
    // MARK: Lifecycle

    init(myCallsign: String? = nil) {
        conversation = CWConversation(myCallsign: myCallsign)
    }

    // MARK: Internal

    // MARK: - Published State

    /// The conversation being tracked
    private(set) var conversation: CWConversation

    /// Current speaker identity
    private(set) var currentSpeaker: StationIdentity = .unknown

    // MARK: - Configuration

    /// Minimum frequency change (Hz) to consider a speaker switch
    let frequencyChangeThreshold: Double = 30

    /// Number of consecutive stable blocks required before confirming frequency change
    let frequencyStableBlocks: Int = 3

    /// Maximum messages to keep in conversation
    let maxMessages: Int = 100

    // MARK: - Public API

    /// Process a new transcript entry with optional frequency info
    /// - Parameters:
    ///   - entry: The decoded transcript entry
    ///   - frequency: Current detected frequency in Hz (if available)
    func processEntry(_ entry: CWTranscriptEntry, frequency: Double?) {
        let text = entry.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            return
        }

        // Check for speaker change
        let speakerChanged = detectSpeakerChange(text: text, frequency: frequency)

        if speakerChanged {
            // Complete the previous message and start a new one
            commitCurrentMessage()
            startNewMessage(frequency: frequency)
        }

        // Append text to current message
        appendToCurrentMessage(text: text, elements: entry.elements)

        // Check for callsign patterns that help identify speakers
        updateSpeakerIdentity(from: text, frequency: frequency)

        // Trim if needed
        conversation.trimToMaxMessages(maxMessages)
    }

    /// Process a word space (potential end of transmission)
    func processWordSpace() {
        // Word spaces within a transmission are normal
        // We use frequency changes and prosigns for turn detection
    }

    /// Reset the tracker for a new session
    func reset() {
        let myCallsign = conversation.myCallsign
        conversation = CWConversation(myCallsign: myCallsign)
        currentSpeaker = .unknown
        lastFrequency = nil
        frequencyStableCount = 0
        pendingFrequency = nil
    }

    /// Set the user's callsign
    func setMyCallsign(_ callsign: String?) {
        conversation.myCallsign = callsign
    }

    // MARK: Private

    // MARK: - Private State

    /// Last stable frequency
    private var lastFrequency: Double?

    /// Count of consecutive blocks at current frequency
    private var frequencyStableCount: Int = 0

    /// Frequency being evaluated for stability
    private var pendingFrequency: Double?

    /// Prosigns that indicate end of transmission / turn change
    private let turnProsigns: Set<String> = ["K", "KN", "BK", "SK", "AR"]

    /// Prosigns that indicate start of identification
    private let identityProsigns: Set<String> = ["DE", "CQ"]

    // MARK: - Turn Detection

    /// Detect if the speaker has changed based on frequency and prosigns
    private func detectSpeakerChange(text: String, frequency: Double?) -> Bool {
        var shouldChange = false

        // Check frequency-based turn detection
        if let freq = frequency {
            shouldChange = shouldChange || detectFrequencyChange(freq)
        }

        // Check prosign-based turn detection
        shouldChange = shouldChange || detectProsignTurn(text)

        return shouldChange
    }

    /// Detect speaker change from frequency shift
    private func detectFrequencyChange(_ frequency: Double) -> Bool {
        guard let lastFreq = lastFrequency else {
            // First frequency - establish baseline
            lastFrequency = frequency
            frequencyStableCount = 1
            return false
        }

        let delta = abs(frequency - lastFreq)

        if delta > frequencyChangeThreshold {
            // Significant frequency change detected
            if let pending = pendingFrequency, abs(frequency - pending) < frequencyChangeThreshold {
                // Same as pending frequency - increment stability counter
                frequencyStableCount += 1
                if frequencyStableCount >= frequencyStableBlocks {
                    // Frequency is stable - confirm speaker change
                    lastFrequency = frequency
                    pendingFrequency = nil
                    frequencyStableCount = 0
                    return true
                }
            } else {
                // New frequency candidate
                pendingFrequency = frequency
                frequencyStableCount = 1
            }
        } else {
            // Frequency stable - reset pending
            pendingFrequency = nil
            frequencyStableCount = 0
        }

        return false
    }

    /// Detect speaker turn from prosigns in text
    private func detectProsignTurn(_ text: String) -> Bool {
        let words = text.uppercased().components(separatedBy: .whitespaces)

        // Check for turn-ending prosigns at the end of text
        if let lastWord = words.last, turnProsigns.contains(lastWord) {
            return true
        }

        // Check for DE at the start (new station identifying)
        if words.first == "DE" {
            return true
        }

        // Check for CQ (new CQ call)
        if words.contains("CQ") {
            return true
        }

        return false
    }

    // MARK: - Message Management

    /// Start a new message
    private func startNewMessage(frequency: Double?) {
        let message = CWConversationMessage(
            timestamp: Date(),
            frequency: frequency,
            stationId: currentSpeaker
        )
        conversation.addMessage(message)
    }

    /// Append text to the current message
    private func appendToCurrentMessage(text: String, elements: [CWTextElement]) {
        if conversation.messages.isEmpty {
            // Start first message
            startNewMessage(frequency: lastFrequency)
        }

        conversation.updateLastMessage { message in
            message.appendText(text)
        }
    }

    /// Mark current message as complete
    private func commitCurrentMessage() {
        conversation.completeLastMessage()
    }

    // MARK: - Speaker Identification

    /// Update speaker identity based on callsign patterns in text
    private func updateSpeakerIdentity(from text: String, frequency: Double?) {
        let words = text.uppercased().components(separatedBy: .whitespaces)

        // Look for "DE CALLSIGN" pattern
        for (index, word) in words.enumerated() where word == "DE" {
            if index + 1 < words.count {
                let potentialCallsign = words[index + 1]
                if CallsignDetector.extractCallsigns(from: potentialCallsign).contains(
                    potentialCallsign
                ) {
                    // Found callsign after DE
                    assignCallsignToCurrentSpeaker(potentialCallsign, frequency: frequency)
                }
            }
        }

        // Look for "CQ CQ CQ DE CALLSIGN" pattern
        if let deIndex = words.firstIndex(of: "DE") {
            let beforeDE = Array(words[..<deIndex])
            if beforeDE.contains("CQ"), deIndex + 1 < words.count {
                let potentialCallsign = words[deIndex + 1]
                if CallsignDetector.extractCallsigns(from: potentialCallsign).contains(
                    potentialCallsign
                ) {
                    assignCallsignToCurrentSpeaker(potentialCallsign, frequency: frequency)
                }
            }
        }
    }

    /// Assign a callsign to the current speaker
    private func assignCallsignToCurrentSpeaker(_ callsign: String, frequency: Double?) {
        // Check if this is my callsign
        if let myCall = conversation.myCallsign?.uppercased(), callsign.uppercased() == myCall {
            currentSpeaker = .me
        } else {
            currentSpeaker = .other(callsign: callsign)
        }

        // Update the current message's station identity
        conversation.updateLastMessage { message in
            message.stationId = currentSpeaker
        }

        // Update frequency map
        if let freq = frequency {
            conversation.frequencyMap[callsign] = freq
        }
    }
}
