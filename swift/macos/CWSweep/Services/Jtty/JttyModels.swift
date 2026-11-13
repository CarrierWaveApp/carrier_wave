import Foundation

// MARK: - JttyDecodeResult

/// One decoder update published by the jtty-sidecar helper: a new message or
/// a longer prefix of one that is still arriving. `messageId` is stable while
/// a message grows; `isComplete` is set on the frame that carried EOM.
struct JttyDecodeResult: Equatable, Sendable {
    let messageId: Int64
    /// Absolute 12 kHz sample index in the client's own receive stream.
    let startSample: Int64
    /// Audio frequency in Hz.
    let frequency: Float
    let isComplete: Bool
    let text: String
}

// MARK: - JttyTxRendering

/// A message the helper rendered to audio, ready to key up and play.
struct JttyTxRendering: Sendable {
    /// The text as transmitted after the helper's normalisation.
    let canonicalText: String
    /// Number of 1.888 s frames the message took.
    let frames: Int
    let sampleRate: Int
    let samples: [Int16]
}

// MARK: - JttyExchangeProfile

/// How ambiguous exchange text is read when packing (`tx_request.profile`).
enum JttyExchangeProfile: Int, CaseIterable, Identifiable, Codable, Sendable {
    case serial = 0
    case fieldDay = 1
    case rttyRoundup = 2

    // MARK: Internal

    var id: Int {
        rawValue
    }

    var label: String {
        switch self {
        case .serial: "Serial number (599 nnn)"
        case .fieldDay: "Field Day (class section)"
        case .rttyRoundup: "RTTY Roundup (serial or state)"
        }
    }

    var sidecarValue: Int32 {
        Int32(rawValue)
    }
}

// MARK: - JttySidecarStatus

/// Lifecycle of the helper process behind the modem.
enum JttySidecarStatus: Equatable, Sendable {
    case notInstalled
    case installing(Double)
    case stopped
    case starting
    case running(version: String)
    case failed(String)

    // MARK: Internal

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }

    var label: String {
        switch self {
        case .notInstalled: "Helper not installed"
        case let .installing(progress): "Installing helper… \(Int(progress * 100))%"
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case let .running(version): "Running (\(version))"
        case let .failed(reason): "Failed: \(reason)"
        }
    }
}

// MARK: - JttyTerminalEntry

/// One line of the JTTY terminal: received text (updated in place while the
/// message grows), text we sent, or a status note.
struct JttyTerminalEntry: Identifiable, Equatable, Sendable {
    // MARK: Lifecycle

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        date: Date = Date(),
        frequency: Float? = nil,
        text: String,
        isComplete: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.frequency = frequency
        self.text = text
        self.isComplete = isComplete
    }

    // MARK: Internal

    enum Kind: Equatable, Sendable {
        case received(messageId: Int64)
        case sent
        case info
        case error
    }

    let id: String
    let kind: Kind
    /// Start of the message on the air (received) or when it was queued (sent).
    var date: Date
    var frequency: Float?
    var text: String
    var isComplete: Bool

    var isReceived: Bool {
        if case .received = kind {
            return true
        }
        return false
    }
}
