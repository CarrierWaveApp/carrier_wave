import SwiftUI

/// Compact inline recording player shown in activation detail and sessions list.
/// Tapping navigates to the full-screen RecordingPlayerView.
struct CompactRecordingPlayer: View {
    // MARK: Internal

    let recording: WebSDRRecording
    let qsos: [QSO]

    @Bindable var engine: RecordingPlaybackEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            waveformSection
            receiverInfoRow
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            await loadIfNeeded()
        }
    }

    // MARK: Private

    // MARK: - Helpers

    private var qsoOffsets: [TimeInterval] {
        let start = recording.startedAt
        return qsos.map { $0.timestamp.timeIntervalSince(start) }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(.red)
            Text("Recording")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                engine.togglePlayPause()
            } label: {
                Image(
                    systemName: engine.isPlaying
                        ? "pause.circle.fill" : "play.circle.fill"
                )
                .font(.title2)
            }
            .buttonStyle(.borderless)

            Text(formatTime(engine.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        RecordingWaveformView(
            amplitudes: engine.amplitudeEnvelope,
            duration: engine.duration,
            currentTime: engine.currentTime,
            qsoOffsets: qsoOffsets,
            activeQSOIndex: engine.activeQSOIndex,
            height: 40,
            seekable: true,
            onSeek: { time in engine.seek(to: time) }
        )
    }

    // MARK: - Receiver Info

    private var receiverInfoRow: some View {
        HStack(spacing: 8) {
            Text(recording.kiwisdrName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(formatFrequency(recording.frequencyKHz))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(recording.mode)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(recording.formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func loadIfNeeded() async {
        guard !engine.isLoaded, let fileURL = recording.fileURL else {
            return
        }
        let timestamps = qsos.sorted { $0.timestamp < $1.timestamp }
            .map(\.timestamp)
        try? engine.load(
            fileURL: fileURL,
            qsoTimestamps: timestamps,
            recordingStart: recording.startedAt
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatFrequency(_ kHz: Double) -> String {
        let mHz = kHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }
}
