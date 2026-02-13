import SwiftUI

/// Amplitude waveform visualization with QSO markers and playback head.
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

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // Amplitude bars
                amplitudeBars(width: width)

                // QSO markers
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
