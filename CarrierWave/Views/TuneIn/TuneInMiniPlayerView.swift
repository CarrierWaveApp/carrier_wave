import CarrierWaveCore
import SwiftUI

// MARK: - TuneInMiniPlayerView

/// Persistent mini player bar shown above the tab bar when tuned in.
/// Tap to expand to the full player sheet.
struct TuneInMiniPlayerView: View {
    // MARK: Internal

    let manager: TuneInManager

    var body: some View {
        if manager.isActive, let spot = manager.spot {
            miniBar(spot: spot)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: manager.isActive)
        }
    }

    // MARK: Private

    private func miniBar(spot: TuneInSpot) -> some View {
        Button {
            manager.showExpandedPlayer = true
        } label: {
            HStack(spacing: 10) {
                liveIndicator
                spotInfo(spot)
                Spacer()
                receiverName
                audioControls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $manager.showExpandedPlayer) {
            TuneInExpandedPlayerView(manager: manager)
        }
    }

    private var liveIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(manager.isStreaming ? .red : .gray)
                .frame(width: 8, height: 8)
                .opacity(manager.isStreaming ? 1 : 0.5)
            Text(manager.isStreaming ? "LIVE" : "...")
                .font(.caption2.weight(.bold))
                .foregroundStyle(manager.isStreaming ? .red : .secondary)
        }
    }

    private func spotInfo(_ spot: TuneInSpot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(spot.callsign)
                .font(.subheadline.weight(.semibold).monospaced())
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(FrequencyFormatter.format(spot.frequencyMHz))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(spot.mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var receiverName: some View {
        if let name = manager.session.receiver?.name {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var audioControls: some View {
        HStack(spacing: 12) {
            // Mute/unmute
            Button {
                manager.toggleMute()
            } label: {
                Image(systemName: manager.session.isMuted
                    ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            // Close
            Button {
                Task {
                    await manager.stop()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
