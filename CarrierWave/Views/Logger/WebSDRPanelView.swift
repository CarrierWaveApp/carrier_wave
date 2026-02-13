import SwiftData
import SwiftUI

// MARK: - WebSDRPanelView

/// Logger panel showing WebSDR connection status and recording controls.
/// Shown when user enters the WEBSDR command.
struct WebSDRPanelView: View {
    // MARK: Internal

    let webSDRSession: WebSDRSession
    let myGrid: String?
    let frequencyMHz: Double?
    let mode: String?
    let loggingSessionId: UUID?
    let modelContext: ModelContext?
    let onDismiss: () -> Void

    @State var showPicker = false

    var levelColor: Color {
        let level = webSDRSession.peakLevel
        if level > 0.8 {
            return .red
        } else if level > 0.5 {
            return .yellow
        }
        return .green
    }

    var formattedDuration: String {
        let total = Int(webSDRSession.recordingDuration)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var bufferColor: Color {
        let fill = webSDRSession.bufferFillRatio
        if fill < 0.15 || fill > 0.9 {
            return .orange
        }
        return .green
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .sheet(isPresented: $showPicker) {
            WebSDRPickerSheet(
                myGrid: myGrid,
                onSelect: { receiver in
                    showPicker = false
                    Task { await startRecording(receiver: receiver) }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Private

    // MARK: - Helpers

    private var headerColor: Color {
        switch webSDRSession.state {
        case .recording: .red
        case .paused: .orange
        case .connecting,
             .reconnecting: .blue
        case .error: .orange
        case .idle: .secondary
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: webSDRSession.state.statusIcon)
                .foregroundStyle(headerColor)
                .symbolEffect(.pulse, isActive: webSDRSession.state == .recording)

            Text("WebSDR")
                .font(.headline)

            if webSDRSession.state == .recording ||
                webSDRSession.state.isActive
            {
                recordingBadge
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    private var recordingBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text(formattedDuration)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.red.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var content: some View {
        switch webSDRSession.state {
        case .idle:
            idleView
        case .connecting:
            connectingView
        case let .reconnecting(attempt):
            reconnectingView(attempt: attempt)
        case .recording,
             .paused:
            recordingView
        case let .error(message):
            errorView(message)
        }
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Record your session from a nearby WebSDR")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showPicker = true
            } label: {
                Label("Choose WebSDR", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var connectingView: some View {
        VStack(spacing: 12) {
            ProgressView()

            if let name = webSDRSession.receiver?.name {
                Text("Connecting to \(name)...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connecting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var recordingView: some View {
        VStack(spacing: 12) {
            // Receiver info
            if let receiver = webSDRSession.receiver {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(receiver.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(receiver.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let dist = receiver.formattedDistance {
                        Text(dist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Tuning info
            tuningInfoRow

            // Level meter
            levelMeter

            // Buffer health indicator
            bufferIndicator

            // Audio engine error (diagnostic)
            if let error = webSDRSession.audioEngine?.startError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            // Controls
            HStack(spacing: 16) {
                // Mute/unmute toggle
                Button {
                    webSDRSession.toggleMute()
                } label: {
                    Image(
                        systemName: webSDRSession.isMuted
                            ? "speaker.slash.fill" : "speaker.wave.2.fill"
                    )
                }
                .buttonStyle(.bordered)
                .tint(webSDRSession.isMuted ? .secondary : .blue)

                if webSDRSession.state == .paused {
                    Button {
                        Task { await webSDRSession.resume() }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                } else {
                    Button {
                        Task { await webSDRSession.pause() }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    Task { await webSDRSession.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }

            // File location, share, and browser link
            HStack {
                if let fileURL = webSDRSession.recordingFileURL {
                    Text("WebSDRRecordings/")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ShareLink(item: fileURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Spacer()
                }

                browserLink
            }
        }
        .padding()
    }
}
