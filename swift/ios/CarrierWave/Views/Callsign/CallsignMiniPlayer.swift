import CarrierWaveCore
import CarrierWaveData
import SwiftUI

/// Compact mini player bar shown at the bottom of CallsignHistoryView
/// when a recording segment is selected for playback.
struct CallsignMiniPlayer: View {
    // MARK: Internal

    let recording: WebSDRRecording
    @Bindable var engine: RecordingPlaybackEngine

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            HStack(spacing: 12) {
                playPauseButton
                infoColumn
                Spacer()
                timeLabel
                fullPlayerLink
                closeButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: Private

    private var progressBar: some View {
        GeometryReader { geo in
            let fraction = engine.duration > 0
                ? engine.currentTime / engine.duration
                : 0
            Rectangle()
                .fill(Color.orange)
                .frame(width: geo.size.width * fraction)
        }
        .frame(height: 3)
        .background(Color(.systemGray5))
    }

    private var playPauseButton: some View {
        Button {
            engine.togglePlayPause()
        } label: {
            Image(
                systemName: engine.isPlaying
                    ? "pause.circle.fill" : "play.circle.fill"
            )
            .font(.title2)
            .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recording.kiwisdrName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(FrequencyFormatter.formatWithUnit(
                recording.frequencyKHz / 1_000.0
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var timeLabel: some View {
        Text(formatTime(engine.currentTime))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var fullPlayerLink: some View {
        NavigationLink {
            RecordingPlayerView(
                recording: recording,
                engine: engine
            )
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
