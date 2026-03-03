import SwiftUI

// MARK: - TuneInMiniPlayerView

/// Persistent mini player bar above the tab bar (Apple Music-style).
/// Shows callsign, frequency, mode, audio level, mute and close controls.
/// Tap to expand to the full player sheet.
struct TuneInMiniPlayerView: View {
    // MARK: Internal

    let manager: TuneInManager

    var body: some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    // MARK: Private

    private var levelColor: Color {
        let level = manager.session.peakLevel
        if level > 0.8 {
            return .red
        }
        if level > 0.5 {
            return .yellow
        }
        return .green
    }

    private var content: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                liveIndicator
                spotInfo
                Spacer()
                audioLevelBar
            }
            .contentShape(Rectangle())
            .onTapGesture {
                manager.showExpandedPlayer = true
            }

            muteButton
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var liveIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(manager.isStreaming ? .red : .orange)
                .frame(width: 8, height: 8)

            Text(manager.isStreaming ? "LIVE" : "...")
                .font(.caption2.weight(.bold))
                .foregroundStyle(manager.isStreaming ? .red : .orange)
        }
    }

    @ViewBuilder
    private var spotInfo: some View {
        if let spot = manager.spot {
            VStack(alignment: .leading, spacing: 1) {
                Text(spot.callsign)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(FrequencyFormatter.format(spot.frequencyMHz))
                        .font(.caption.monospaced())
                    Text(spot.mode)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var audioLevelBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray5))
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelColor)
                    .frame(
                        width: geometry.size.width
                            * CGFloat(manager.session.peakLevel)
                    )
            }
        }
        .frame(width: 40, height: 4)
    }

    private var muteButton: some View {
        Button {
            manager.toggleMute()
        } label: {
            Image(
                systemName: manager.session.isMuted
                    ? "speaker.slash.fill" : "speaker.wave.2.fill"
            )
            .font(.body)
            .foregroundStyle(.primary)
            .frame(width: 32, height: 32)
        }
    }

    private var closeButton: some View {
        Button {
            Task {
                await manager.stop()
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
    }
}
