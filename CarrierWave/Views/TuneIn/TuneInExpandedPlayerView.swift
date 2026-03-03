import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - TuneInExpandedPlayerView

/// Full expanded player sheet shown when tapping the mini player bar.
/// Shows receiver details, audio level, volume, and action buttons.
struct TuneInExpandedPlayerView: View {
    // MARK: Internal

    let manager: TuneInManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let spot = manager.spot {
                        spotHeader(spot)
                        receiverCard
                        audioSection
                        if manager.isCWMode {
                            cwTranscriptSection
                        }
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
    }

    // MARK: Private

    // MARK: - Spot Header

    private func spotHeader(_ spot: TuneInSpot) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(spot.callsign)
                    .font(.title2.weight(.bold).monospaced())

                Spacer()

                statusBadge
            }

            HStack(spacing: 8) {
                if let parkRef = spot.parkRef {
                    Label(parkRef, systemImage: "tree.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else if let summit = spot.summitCode {
                    Label(summit, systemImage: "mountain.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.brown)
                }
                if let name = spot.parkName ?? spot.summitName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text(FrequencyFormatter.format(spot.frequencyMHz))
                    .font(.headline.monospaced())
                Text(spot.mode)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(spot.band)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(manager.isStreaming ? .red : .orange)
                .frame(width: 8, height: 8)
            Text(manager.session.state.statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(manager.isStreaming ? .red : .secondary)
            if manager.isStreaming {
                Text(formattedDuration)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Receiver Card

    private var receiverCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Receiver")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if let receiver = manager.session.receiver {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receiver.name)
                            .font(.subheadline.weight(.medium))
                        Text(receiver.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let dist = receiver.formattedDistance {
                            Text(dist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    changeReceiverButton
                }
            } else {
                Text("Searching for receiver...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var changeReceiverButton: some View {
        Button {
            showReceiverPicker = true
        } label: {
            Text("Change")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .sheet(isPresented: $showReceiverPicker) {
            WebSDRPickerSheet(
                myGrid: manager.spot?.grid,
                currentBand: manager.spot?.band,
                onSelect: { receiver in
                    Task {
                        await handleReceiverChange(receiver)
                    }
                }
            )
        }
    }

    @State private var showReceiverPicker = false

    // MARK: - Audio Section

    private var audioSection: some View {
        VStack(spacing: 12) {
            // Audio level meter
            audioLevelMeter

            // Volume control
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: .constant(1.0), in: 0 ... 1)
                    .tint(.blue)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var levelColor: Color {
        let level = manager.session.peakLevel
        if level > 0.8 { return .red }
        if level > 0.5 { return .yellow }
        return .green
    }

    // MARK: - CW Transcript

    private var cwTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("CW Transcript", systemImage: "waveform")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                cwTranscriptStatus
            }

            let cw = manager.cwTranscription
            if cw.conversation.isEmpty, cw.currentLine.isEmpty {
                cwEmptyState
            } else {
                CWChatView(
                    conversation: cw.conversation,
                    callsignLookup: nil
                )
                .frame(minHeight: 150, maxHeight: 300)
            }

            // Detected callsigns
            if !manager.cwTranscription.detectedCallsigns.isEmpty {
                detectedCallsignsPills
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var cwTranscriptStatus: some View {
        let cw = manager.cwTranscription
        if cw.isListening {
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("\(cw.estimatedWPM) WPM")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cwEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Listening for CW...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Decoded Morse will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var detectedCallsignsPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(
                    manager.cwTranscription.detectedCallsigns,
                    id: \.self
                ) { callsign in
                    Text(callsign)
                        .font(.caption.weight(.medium).monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            actionButton(
                title: manager.session.isMuted ? "Unmute" : "Mute",
                icon: manager.session.isMuted
                    ? "speaker.slash.fill" : "speaker.wave.2.fill"
            ) {
                manager.toggleMute()
            }

            if let url = manager.session.webURL {
                Link(destination: url) {
                    VStack(spacing: 4) {
                        Image(systemName: "safari")
                            .font(.title3)
                        Text("Open")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            actionButton(title: "Stop", icon: "stop.fill") {
                Task {
                    await manager.stop()
                    manager.showExpandedPlayer = false
                }
            }
            .tint(.red)
        }
    }

    private func actionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        let total = Int(manager.session.recordingDuration)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func handleReceiverChange(_ receiver: KiwiSDRReceiver) async {
        guard let spot = manager.spot else { return }
        // Stop current, reconnect to new receiver
        await manager.session.finalize()
        manager.session.state = .idle
        // Re-tune with new receiver
        await manager.session.start(
            receiver: receiver,
            frequencyMHz: spot.frequencyMHz,
            mode: spot.mode,
            loggingSessionId: UUID(),
            modelContext: modelContext
        )
    }
}
