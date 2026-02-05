import CarrierWaveCore
import Foundation

// MARK: - StationIdentity

/// Identifies which station is transmitting in a CW conversation
enum StationIdentity: Equatable, Hashable {
    /// The user's own station
    case me
    /// The other station (with optional callsign if known)
    case other(callsign: String?)
    /// Not yet determined
    case unknown

    // MARK: Internal

    /// Display name for UI
    var displayName: String {
        switch self {
        case .me:
            "Me"
        case let .other(callsign):
            callsign ?? "Other Station"
        case .unknown:
            "Unknown"
        }
    }

    /// The callsign if known
    var callsign: String? {
        switch self {
        case .me:
            nil // User's callsign would need to be passed in separately
        case let .other(callsign):
            callsign
        case .unknown:
            nil
        }
    }

    /// Whether this identity has an associated callsign
    var hasCallsign: Bool {
        callsign != nil
    }
}

// MARK: - CWConversationMessage

/// A single message in a CW conversation (one station's transmission)
struct CWConversationMessage: Identifiable, Equatable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        frequency: Double? = nil,
        text: String = "",
        elements: [CWTextElement] = [],
        stationId: StationIdentity = .unknown,
        isComplete: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.frequency = frequency
        self.text = text
        self.elements = elements
        self.stationId = stationId
        self.isComplete = isComplete
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    /// Frequency in Hz when this message was received
    let frequency: Double?
    /// Raw decoded text
    var text: String
    /// Parsed elements with highlighting
    var elements: [CWTextElement]
    /// Which station sent this message
    var stationId: StationIdentity
    /// Whether this message is complete (station stopped transmitting)
    var isComplete: Bool

    /// Append text to this message and re-parse elements
    mutating func appendText(_ newText: String) {
        if text.isEmpty {
            text = newText
        } else {
            text += " " + newText
        }
        elements = CallsignDetector.parseElements(from: text)
    }
}

// MARK: - CWConversation

/// A CW conversation being transcribed, containing messages from multiple stations
struct CWConversation: Identifiable {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        myCallsign: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.myCallsign = myCallsign
        messages = []
        frequencyMap = [:]
    }

    // MARK: Internal

    let id: UUID
    let startTime: Date

    /// User's callsign (for identifying "me" in the conversation)
    var myCallsign: String?

    /// All messages in the conversation
    var messages: [CWConversationMessage]

    /// Mapping of callsign to last known frequency
    var frequencyMap: [String: Double]

    /// The other station's callsign (primary contact)
    var theirCallsign: String? {
        // Find the first callsign that isn't ours
        for message in messages {
            if case let .other(callsign) = message.stationId, let cs = callsign {
                return cs
            }
        }
        return nil
    }

    /// Whether the conversation has any content
    var isEmpty: Bool {
        messages.isEmpty
    }

    /// Total text content for the entire conversation
    var fullText: String {
        messages.map(\.text).joined(separator: " ")
    }

    // MARK: - Mutation

    /// Add a new message to the conversation
    mutating func addMessage(_ message: CWConversationMessage) {
        messages.append(message)

        // Update frequency map if we have a callsign
        if let callsign = message.stationId.callsign, let freq = message.frequency {
            frequencyMap[callsign] = freq
        }
    }

    /// Update the last message (for messages still being received)
    mutating func updateLastMessage(_ update: (inout CWConversationMessage) -> Void) {
        guard !messages.isEmpty else {
            return
        }
        update(&messages[messages.count - 1])
    }

    /// Mark the last message as complete
    mutating func completeLastMessage() {
        guard !messages.isEmpty else {
            return
        }
        messages[messages.count - 1].isComplete = true
    }

    /// Clear all messages
    mutating func clear() {
        messages.removeAll()
        frequencyMap.removeAll()
    }

    /// Trim old messages to prevent unbounded growth
    mutating func trimToMaxMessages(_ maxCount: Int) {
        if messages.count > maxCount {
            messages.removeFirst(messages.count - maxCount)
        }
    }
}
