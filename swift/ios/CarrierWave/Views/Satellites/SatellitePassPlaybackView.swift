import AVFAudio
import SwiftUI

// MARK: - SatellitePassPlaybackView

/// Playback for a recorded pass inside the quick-log sheet: play/pause, a
/// scrubber, and one chip per tap mark — tapping a mark rewinds to 5 s
/// before it so the operator can re-copy the callsign and grid.
struct SatellitePassPlaybackView: View {
    // MARK: Internal

    let recording: SatellitePassRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                HStack(spacing: 12) {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause pass audio" : "Play pass audio")
                    Slider(
                        value: Binding(
                            get: { player?.currentTime ?? 0 },
                            set: { player?.currentTime = $0 }
                        ),
                        in: 0 ... max(duration, 1)
                    )
                    Text(timeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 88, alignment: .trailing)
                }
            }
            if !recording.markOffsets.isEmpty {
                markChips
            }
        }
        .onAppear {
            preparePlayer()
        }
        .onDisappear {
            player?.stop()
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        }
    }

    // MARK: Private

    @State private var player: AVAudioPlayer?

    private var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    private var duration: TimeInterval {
        player?.duration ?? 0
    }

    private var timeLabel: String {
        "\(Self.clock(player?.currentTime ?? 0)) / \(Self.clock(duration))"
    }

    private var markChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(recording.markOffsets.enumerated()), id: \.offset) { index, offset in
                    Button {
                        seek(to: offset)
                    } label: {
                        Text("#\(index + 1) \(Self.clock(offset))")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play from mark \(index + 1)")
                }
            }
        }
    }

    private static func clock(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func preparePlayer() {
        guard player == nil,
              let directory = try? SatellitePassRecordingStore.defaultDirectory()
        else {
            return
        }
        let url = SatellitePassRecordingStore.audioURL(for: recording, in: directory)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
    }

    private func togglePlayback() {
        guard let player else {
            return
        }
        if player.isPlaying {
            player.pause()
        } else {
            activatePlaybackSession()
            player.play()
        }
    }

    /// Rewind to 5 s before the mark — the callsign was said just before
    /// the operator's tap.
    private func seek(to markOffset: TimeInterval) {
        guard let player else {
            return
        }
        player.currentTime = max(0, markOffset - 5)
        activatePlaybackSession()
        player.play()
    }

    private func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }
}
