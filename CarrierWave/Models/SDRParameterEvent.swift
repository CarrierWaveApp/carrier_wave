import CarrierWaveData
import Foundation

// MARK: - SDRParameterEvent

/// A recorded parameter change during an SDR recording session.
/// Captures when the operator changed frequency, mode, or recording lifecycle
/// so the recording can be accurately segmented for playback and rendering.
struct SDRParameterEvent: Codable, Sendable, Equatable {
    /// What kind of event occurred
    enum ChangeType: String, Codable, Sendable {
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
    let type: ChangeType

    /// When the event occurred
    let timestamp: Date

    /// Offset in seconds from recording start
    let offsetSeconds: Double

    /// Previous value (frequency in kHz as string, mode name, or empty for lifecycle events)
    let oldValue: String

    /// New value (frequency in kHz as string, mode name, receiver host, or empty)
    let newValue: String
}

// MARK: - SDRRecordingSegment

/// A contiguous segment of an SDR recording with consistent tuning parameters.
/// Built from the initial recording parameters plus any parameter change events.
struct SDRRecordingSegment: Sendable, Equatable {
    // MARK: Lifecycle

    nonisolated init(
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

    // MARK: Internal

    /// Offset from recording start in seconds
    let startOffset: TimeInterval

    /// End offset in seconds (nil for the final/current segment)
    let endOffset: TimeInterval?

    /// Tuned frequency in kHz
    let frequencyKHz: Double

    /// Operating mode (CW, SSB, etc.)
    let mode: String

    /// Whether this segment is a silence gap (pause or SDR disconnect)
    let isSilence: Bool

    /// Duration of this segment in seconds (requires recording duration for last segment)
    func duration(recordingDuration: TimeInterval) -> TimeInterval {
        let end = endOffset ?? recordingDuration
        return end - startOffset
    }
}
