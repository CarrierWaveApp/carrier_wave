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

    @State private var showPicker = false

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

    private var levelColor: Color {
        let level = webSDRSession.peakLevel
        if level > 0.8 {
            return .red
        } else if level > 0.5 {
            return .yellow
        }
        return .green
    }

    private var formattedDuration: String {
        let total = Int(webSDRSession.recordingDuration)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var header: some View {
        HStack {
            Image(systemName: webSDRSession.state.statusIcon)
                .foregroundStyle(headerColor)
                .symbolEffect(.pulse, isActive: webSDRSession.state == .recording)

            Text("WebSDR")
                .font(.headline)

            if webSDRSession.state == .recording {
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
        case .connecting,
             .reconnecting:
            connectingView
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

            // Level meter
            levelMeter

            // Controls
            HStack(spacing: 16) {
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
        }
        .padding()
    }

    private var levelMeter: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))

                // Level bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: geometry.size.width * CGFloat(webSDRSession.peakLevel))
                    .animation(.linear(duration: 0.1), value: webSDRSession.peakLevel)
            }
        }
        .frame(height: 8)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                showPicker = true
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func startRecording(receiver: KiwiSDRReceiver) async {
        guard let loggingSessionId,
              let modelContext,
              let frequencyMHz,
              let mode
        else {
            return
        }

        await webSDRSession.start(
            receiver: receiver,
            frequencyMHz: frequencyMHz,
            mode: mode,
            loggingSessionId: loggingSessionId,
            modelContext: modelContext
        )
    }
}

import SwiftData
