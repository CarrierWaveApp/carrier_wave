import CarrierWaveCore
import SwiftUI

// MARK: - TuneInExpandedPlayerView

/// Full expanded player sheet with receiver details, audio level, volume,
/// CW transcript, and action buttons.
struct TuneInExpandedPlayerView: View {
    // MARK: Internal

    let manager: TuneInManager

    @Environment(\.modelContext) var modelContext

    @State var showReceiverPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let spot = manager.spot {
                        spotHeader(spot)
                        qsyAlertBanner
                        receiverSuggestionBanner
                        receiverCard
                        audioSection
                        actionButtons
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tune In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        manager.showExpandedPlayer = false
                    }
                }
            }
        }
        .sheet(isPresented: $showReceiverPicker) {
            receiverPickerSheet
        }
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

    /// Clip bookmarks collected so far in this session
    private var clipCount: Int {
        manager.session.clipBookmarks.count
    }

    private var sessionStatus: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(manager.isStreaming ? .red : .orange)
                .frame(width: 8, height: 8)

            Text(manager.isStreaming ? "LIVE" : manager.session.state.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(manager.isStreaming ? .red : .orange)

            if manager.session.recordingDuration > 0 {
                Text(formatDuration(manager.session.recordingDuration))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Receiver Card

    private var receiverCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Receiver", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let receiver = manager.session.receiver {
                VStack(alignment: .leading, spacing: 4) {
                    Text(receiver.name)
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        Text(receiver.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let dist = receiver.formattedDistance {
                            Text(dist + " from activator")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                audioLevelMeter

                HStack {
                    Spacer()
                    Button("Change Receiver") {
                        showReceiverPicker = true
                    }
                    .font(.caption)
                }
            } else {
                Text(manager.session.state.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        VStack(spacing: 12) {
            // Volume control
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text("Volume control in Control Center")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var audioLevelMeter: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))
                RoundedRectangle(cornerRadius: 3)
                    .fill(levelColor)
                    .frame(
                        width: geometry.size.width
                            * CGFloat(manager.session.peakLevel)
                    )
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Action Buttons & Spot Header

extension TuneInExpandedPlayerView {
    var actionButtons: some View {
        HStack(spacing: 16) {
            muteButton
            clipButton
            openInBrowserButton
        }
    }

    var muteButton: some View {
        Button {
            manager.toggleMute()
        } label: {
            VStack(spacing: 4) {
                Image(
                    systemName: manager.session.isMuted
                        ? "speaker.slash.fill" : "speaker.wave.2.fill"
                )
                .font(.title3)
                Text(manager.session.isMuted ? "Unmute" : "Mute")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    var clipButton: some View {
        Button {
            manager.addClipBookmark()
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bookmark.fill")
                        .font(.title3)
                    if clipCount > 0 {
                        Text("\(clipCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .offset(x: 6, y: -4)
                    }
                }
                Text("Clip")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    var openInBrowserButton: some View {
        Button {
            if let url = manager.session.webURL {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "safari")
                    .font(.title3)
                Text("Open")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(manager.session.webURL == nil)
    }

    var receiverPickerSheet: some View {
        WebSDRPickerSheet(myGrid: manager.spot?.grid, operatingBand: manager.spot?.band) { receiver in
            showReceiverPicker = false
            Task {
                await manager.session.finalize()
                if let spot = manager.spot {
                    await manager.session.start(
                        receiver: receiver,
                        frequencyMHz: spot.frequencyMHz,
                        mode: spot.mode,
                        loggingSessionId: UUID(),
                        modelContext: modelContext
                    )
                }
            }
        }
    }

    func spotHeader(_ spot: TuneInSpot) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(spot.callsign)
                    .font(.title2.weight(.bold).monospaced())
                followButton(spot.callsign)
                Spacer()
                sessionStatus
            }
            spotReferenceRow(spot)
            HStack(spacing: 8) {
                Text(FrequencyFormatter.format(spot.frequencyMHz) + " MHz")
                    .font(.subheadline.monospaced())
                Text(spot.mode)
                    .font(.subheadline)
                Text(spot.band)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    func spotReferenceRow(_ spot: TuneInSpot) -> some View {
        if let parkRef = spot.parkRef {
            HStack(spacing: 4) {
                Image(systemName: "tree.fill")
                    .foregroundStyle(.green)
                Text(parkRef).fontWeight(.medium)
                if let parkName = spot.parkName {
                    Text(parkName).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .font(.subheadline)
        } else if let summitCode = spot.summitCode {
            HStack(spacing: 4) {
                Image(systemName: "mountain.2.fill")
                    .foregroundStyle(.brown)
                Text(summitCode).fontWeight(.medium)
                if let summitName = spot.summitName {
                    Text(summitName).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .font(.subheadline)
        }
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
