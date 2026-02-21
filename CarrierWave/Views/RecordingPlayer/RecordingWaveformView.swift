import SwiftUI

/// Amplitude waveform visualization with QSO markers, span regions,
/// segment boundaries, and playback head.
/// Reused in both compact and full-screen recording players.
struct RecordingWaveformView: View {
    // MARK: Internal

    /// Amplitude samples (0.0 to 1.0)
    let amplitudes: [Float]

    /// Total duration of the recording in seconds
    let duration: TimeInterval

    /// Current playback position in seconds
    let currentTime: TimeInterval

    /// QSO offsets from recording start, in seconds
    let qsoOffsets: [TimeInterval]

    /// Index of the currently active QSO (nil if none)
    let activeQSOIndex: Int?

    /// Height of the waveform
    var height: CGFloat = 40

    /// Whether drag-to-seek is enabled
    var seekable: Bool = false

    /// Called when user drags to seek (time in seconds)
    var onSeek: ((TimeInterval) -> Void)?

    /// Optional callsign labels for QSO markers (must match qsoOffsets count)
    var qsoCallsigns: [String]?

    /// QSO time ranges for span regions (start, end) in seconds
    var qsoRanges: [(start: TimeInterval, end: TimeInterval)] = []

    /// Recording segments for boundary markers
    var segments: [SDRRecordingSegment] = []

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // QSO span regions (behind everything)
                qsoSpanRegions(width: width)

                // Amplitude bars
                amplitudeBars(width: width)

                // Segment boundaries
                segmentBoundaries(width: width)

                // QSO markers (thin lines at start of each QSO)
                ForEach(Array(qsoOffsets.enumerated()), id: \.offset) { index, offset in
                    qsoMarker(
                        at: offset, index: index, width: width
                    )
                }

                // Playback head
                playbackHead(width: width)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(seekable ? seekGesture(width: width) : nil)
        }
        .frame(height: height)
    }

    // MARK: Private

    // MARK: - Subviews

    private func amplitudeBars(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(Array(amplitudes.enumerated()), id: \.offset) { _, amp in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(height: max(2, height * CGFloat(amp)))
            }
        }
        .frame(width: width, height: height)
    }

    private func qsoSpanRegions(width: CGFloat) -> some View {
        ForEach(Array(qsoRanges.enumerated()), id: \.offset) { index, range in
            let startX = xPosition(for: range.start, in: width)
            let endX = xPosition(for: range.end, in: width)
            let spanWidth = max(1, endX - startX)
            let isActive = index == activeQSOIndex

            Rectangle()
                .fill(Color.accentColor.opacity(isActive ? 0.15 : 0.08))
                .frame(width: spanWidth, height: height)
                .position(x: startX + spanWidth / 2, y: height / 2)
        }
    }

    @ViewBuilder
    private func segmentBoundaries(width: CGFloat) -> some View {
        // Show boundary lines at each non-first segment start
        let boundaries = Array(segments.dropFirst())
        ForEach(Array(boundaries.enumerated()), id: \.offset) { _, segment in
            if !segment.isSilence {
                let x = xPosition(for: segment.startOffset, in: width)
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 1, height: height)
                    .position(x: x, y: height / 2)
                    .overlay(alignment: .top) {
                        frequencyLabel(for: segment)
                            .position(x: x, y: -2)
                    }
            }
        }
    }

    private func frequencyLabel(for segment: SDRRecordingSegment) -> some View {
        let mHz = segment.frequencyKHz / 1_000
        let label = mHz == mHz.rounded()
            ? String(format: "%.0f", mHz)
            : String(format: "%.3f", mHz)
        return Text(label)
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
    }

    private func qsoMarker(
        at offset: TimeInterval, index: Int, width: CGFloat
    ) -> some View {
        let x = xPosition(for: offset, in: width)
        let isActive = index == activeQSOIndex

        return Rectangle()
            .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.5))
            .frame(width: isActive ? 2 : 1, height: height)
            .position(x: x, y: height / 2)
    }

    private func playbackHead(width: CGFloat) -> some View {
        let x = xPosition(for: currentTime, in: width)

        return Rectangle()
            .fill(Color.primary)
            .frame(width: 2, height: height + 4)
            .position(x: x, y: height / 2)
    }

    // MARK: - Helpers

    private func xPosition(for time: TimeInterval, in width: CGFloat) -> CGFloat {
        guard duration > 0 else {
            return 0
        }
        let fraction = CGFloat(time / duration)
        return max(0, min(width, fraction * width))
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fraction = max(0, min(1, value.location.x / width))
                let time = TimeInterval(fraction) * duration
                onSeek?(time)
            }
    }
}
