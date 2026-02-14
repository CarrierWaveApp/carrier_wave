import Foundation

// MARK: - SDRParameterEvent

/// A recorded parameter change during an SDR recording session.
/// Captures when the operator changed frequency or mode so the recording
/// can be accurately segmented for playback and rendering.
struct SDRParameterEvent: Codable, Sendable, Equatable {
    /// What kind of parameter changed
    enum ChangeType: String, Codable, Sendable {
        case frequency
        case mode
    }

    /// What changed
    let type: ChangeType

    /// When the change occurred
    let timestamp: Date

    /// Offset in seconds from recording start
    let offsetSeconds: Double

    /// Previous value (frequency in kHz as string, or mode name)
    let oldValue: String

    /// New value (frequency in kHz as string, or mode name)
    let newValue: String
}

// MARK: - SDRRecordingSegment

/// A contiguous segment of an SDR recording with consistent tuning parameters.
/// Built from the initial recording parameters plus any parameter change events.
struct SDRRecordingSegment: Sendable, Equatable {
    /// Offset from recording start in seconds
    let startOffset: TimeInterval

    /// End offset in seconds (nil for the final/current segment)
    let endOffset: TimeInterval?

    /// Tuned frequency in kHz
    let frequencyKHz: Double

    /// Operating mode (CW, SSB, etc.)
    let mode: String

    /// Duration of this segment in seconds (requires recording duration for last segment)
    func duration(recordingDuration: TimeInterval) -> TimeInterval {
        let end = endOffset ?? recordingDuration
        return end - startOffset
    }
}
