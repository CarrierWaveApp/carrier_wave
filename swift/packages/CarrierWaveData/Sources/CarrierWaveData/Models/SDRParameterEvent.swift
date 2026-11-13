import Foundation

// MARK: - SDRParameterEvent

/// A recorded parameter change during an SDR recording session.
/// Captures when the operator changed frequency, mode, or recording lifecycle
/// so the recording can be accurately segmented for playback and rendering.
public struct SDRParameterEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        type: ChangeType,
        timestamp: Date,
        offsetSeconds: Double,
        oldValue: String,
        newValue: String
    ) {
        self.type = type
        self.timestamp = timestamp
        self.offsetSeconds = offsetSeconds
        self.oldValue = oldValue
        self.newValue = newValue
    }

    // MARK: Public

    /// What kind of event occurred
    public enum ChangeType: String, Codable, Sendable {
        /// Frequency changed (oldValue/newValue are kHz strings)
        case frequency
        /// Mode changed (oldValue/newValue are mode names)
        case mode
        /// Recording paused (silence begins)
        case pause
        /// Recording resumed from pause
        case resume
        /// WebSDR disconnected mid-session (silence begins)
        case sdrDisconnected
        /// WebSDR reconnected mid-session (audio resumes)
        case sdrConnected
    }

    /// What happened
    public let type: ChangeType

    /// When the event occurred
    public let timestamp: Date

    /// Offset in seconds from recording start
    public let offsetSeconds: Double

    /// Previous value (frequency in kHz as string, mode name, or empty for lifecycle events)
    public let oldValue: String

    /// New value (frequency in kHz as string, mode name, receiver host, or empty)
    public let newValue: String
}

// MARK: - SDRRecordingSegment

/// A contiguous segment of an SDR recording with consistent tuning parameters.
/// Built from the initial recording parameters plus any parameter change events.
public struct SDRRecordingSegment: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        startOffset: TimeInterval,
        endOffset: TimeInterval?,
        frequencyKHz: Double,
        mode: String,
        isSilence: Bool = false
    ) {
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.frequencyKHz = frequencyKHz
        self.mode = mode
        self.isSilence = isSilence
    }

    // MARK: Public

    /// Offset from recording start in seconds
    public let startOffset: TimeInterval

    /// End offset in seconds (nil for the final/current segment)
    public let endOffset: TimeInterval?

    /// Tuned frequency in kHz
    public let frequencyKHz: Double

    /// Operating mode (CW, SSB, etc.)
    public let mode: String

    /// Whether this segment is a silence gap (pause or SDR disconnect)
    public let isSilence: Bool

    /// Duration of this segment in seconds (requires recording duration for last segment)
    public func duration(recordingDuration: TimeInterval) -> TimeInterval {
        let end = endOffset ?? recordingDuration
        return end - startOffset
    }
}
