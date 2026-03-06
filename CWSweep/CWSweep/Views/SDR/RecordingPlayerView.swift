import CarrierWaveData
import SwiftUI

/// Inline playback controls for a selected recording
struct RecordingPlayerView: View {
    // MARK: Internal

    let recording: WebSDRRecording

    @Bindable var playbackEngine: RecordingPlaybackEngine

    var body: some View {
        VStack(spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.spotCallsign ?? (recording.kiwisdrName.isEmpty ? "Recording" : recording.kiwisdrName))
                    .font(.headline)
                HStack {
                    Text(String(format: "%.1f kHz", recording.frequencyKHz))
                        .monospacedDigit()
                    Text(recording.mode)
                        .foregroundStyle(.secondary)
                    if !recording.kiwisdrName.isEmpty {
                        Text("via \(recording.kiwisdrName)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Scrubber
            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { playbackEngine.currentTime },
                        set: { playbackEngine.seek(to: $0) }
                    ),
                    in: 0 ... max(playbackEngine.duration, 0.01)
                )

                HStack {
                    Text(formatTime(playbackEngine.currentTime))
                    Spacer()
                    Text(formatTime(playbackEngine.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            // Transport controls
            HStack(spacing: 16) {
                Button { playbackEngine.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15")
                }
                .disabled(!playbackEngine.isLoaded)

                Button { playbackEngine.previousQSO() } label: {
                    Image(systemName: "backward.end.fill")
                }
                .disabled(!playbackEngine.isLoaded)

                Button { playbackEngine.togglePlayPause() } label: {
                    Image(systemName: playbackEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .disabled(!playbackEngine.isLoaded)
                .keyboardShortcut(.space, modifiers: [])

                Button { playbackEngine.nextQSO() } label: {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(!playbackEngine.isLoaded)

                Button { playbackEngine.skip(by: 15) } label: {
                    Image(systemName: "goforward.15")
                }
                .disabled(!playbackEngine.isLoaded)

                Spacer()

                // Speed control
                Picker("Speed", selection: $playbackEngine.playbackRate) {
                    Text("0.5x").tag(Float(0.5))
                    Text("1x").tag(Float(1.0))
                    Text("1.5x").tag(Float(1.5))
                    Text("2x").tag(Float(2.0))
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            // Segment info
            if let segment = playbackEngine.activeSegment {
                HStack {
                    Text(String(format: "%.1f kHz", segment.frequencyKHz))
                        .monospacedDigit()
                    Text(segment.mode)
                        .foregroundStyle(.secondary)
                    if segment.isSilence {
                        Text("(silence)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }

            // Transcript
            if let transcript = playbackEngine.transcript {
                Divider()
                transcriptView(transcript)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: Private

    private func transcriptView(_ transcript: SDRRecordingTranscript) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(transcript.lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(formatTime(line.startOffset))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .trailing)

                            if let speaker = line.speakerCallsign {
                                Text(speaker)
                                    .font(.caption.bold())
                                    .foregroundStyle(.blue)
                            }

                            Text(line.words.map(\.text).joined(separator: " "))
                                .font(.caption)
                                .foregroundStyle(
                                    index == playbackEngine.activeTranscriptLineIndex
                                        ? .primary : .secondary
                                )
                        }
                        .id(index)
                        .onTapGesture {
                            playbackEngine.seek(to: line.startOffset)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: playbackEngine.activeTranscriptLineIndex) { _, newIndex in
                if let idx = newIndex {
                    withAnimation { proxy.scrollTo(idx, anchor: .center) }
                }
            }
        }
        .frame(maxHeight: 200)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
