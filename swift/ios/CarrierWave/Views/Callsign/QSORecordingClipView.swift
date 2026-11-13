import SwiftUI

// MARK: - QSORecordingClipView

/// Compact inline recording clip player showing time range with play button.
struct QSORecordingClipView: View {
    // MARK: Internal

    let clip: QSORecordingClip

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text(formattedRange)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .accessibilityLabel("Play recording clip")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var formattedRange: String {
        "\(formatTime(clip.startOffset)) – \(formatTime(clip.endOffset))"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
