import SwiftData
import SwiftUI

// MARK: - WebSDRPanelView Subviews

extension WebSDRPanelView {
    var tuningInfoRow: some View {
        let kiwiMode = webSDRSession.currentKiwiMode
        return HStack {
            // Frequency and mode
            HStack(spacing: 6) {
                Image(systemName: "dial.low.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(FrequencyFormatter.formatWithUnit(
                    webSDRSession.lastFrequencyMHz
                ))
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
                Text(kiwiMode.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary)
                    .clipShape(Capsule())
            }

            Spacer()

            // Filter width
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(kiwiMode.bandwidthDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var browserLink: some View {
        Group {
            if let url = webSDRSession.webURL {
                Link(destination: url) {
                    Label("Open in Browser", systemImage: "safari")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    var levelMeter: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(levelColor)
                        .frame(
                            width: geometry.size.width
                                * CGFloat(webSDRSession.peakLevel)
                        )
                }
            }
            .frame(height: 8)

            HStack {
                Text("Level")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("S\(webSDRSession.sMeter)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    var bufferIndicator: some View {
        HStack(spacing: 6) {
            if webSDRSession.audioEngine?.isBuffering == true {
                ProgressView()
                    .controlSize(.mini)
                Text("Buffering...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(bufferColor)
                    .frame(width: 6, height: 6)
                Text("Buffer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(bufferColor)
                        .frame(
                            width: geometry.size.width
                                * webSDRSession.bufferFillRatio
                        )
                }
            }
            .frame(height: 4)
        }
    }

    func reconnectingView(attempt: Int) -> some View {
        VStack(spacing: 12) {
            ProgressView()

            Text("Connection lost — reconnecting (attempt \(attempt))...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if webSDRSession.recordingDuration > 0 {
                Text(formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                Task { await webSDRSession.stop() }
            } label: {
                Label("Stop Recording", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showPicker = true
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    func startRecording(receiver: KiwiSDRReceiver) async {
        guard let frequencyMHz,
              let mode,
              let loggingSessionId,
              let modelContext
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
