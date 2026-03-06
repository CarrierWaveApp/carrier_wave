import CarrierWaveData
import SwiftData
import SwiftUI

/// Main SDR player view for the content area
struct SDRPlayerView: View {
    // MARK: Internal

    var body: some View {
        @Bindable var manager = tuneInManager

        VStack(spacing: 0) {
            if tuneInManager.isActive {
                activePlayerView
            } else {
                inactiveView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("QSY Detected", isPresented: .init(
            get: { tuneInManager.qsyAlert != nil },
            set: { if !$0 {
                tuneInManager.dismissQSYAlert()
            } }
        )) {
            Button("Retune") {
                Task { await tuneInManager.acceptQSYRetune() }
            }
            Button("Dismiss", role: .cancel) {
                tuneInManager.dismissQSYAlert()
            }
        } message: {
            if let alert = tuneInManager.qsyAlert {
                Text(
                    "\(alert.callsign) moved to \(String(format: "%.1f kHz", alert.newFrequencyMHz * 1_000)) (\(alert.newBand))"
                )
            }
        }
    }

    // MARK: Private

    @Environment(TuneInManager.self) private var tuneInManager
    @Environment(\.modelContext) private var modelContext

    @ViewBuilder
    private var activePlayerView: some View {
        let session = tuneInManager.session

        VStack(spacing: 16) {
            // Connection info
            HStack {
                Image(systemName: session.state.statusIcon)
                    .foregroundStyle(session.state == .recording ? .green : .orange)
                Text(session.state.statusText)
                    .font(.headline)

                Spacer()

                if let spot = tuneInManager.spot {
                    Text(spot.callsign)
                        .font(.title3.bold())
                }
            }
            .padding(.horizontal)

            // Receiver name
            if let receiver = session.receiver {
                HStack {
                    Label(receiver.name, systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let distance = receiver.formattedDistance {
                        Text(distance)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }

            Divider()

            // Frequency & Mode
            HStack(spacing: 16) {
                // Frequency display
                VStack(alignment: .leading) {
                    Text("Frequency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.3f kHz", session.lastFrequencyMHz * 1_000))
                        .font(.system(.title2, design: .monospaced))
                }

                // Tuning buttons
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        tuneButton(label: "-1k", offset: -1.0)
                        tuneButton(label: "-100", offset: -0.1)
                        tuneButton(label: "+100", offset: 0.1)
                        tuneButton(label: "+1k", offset: 1.0)
                    }
                }

                Spacer()

                // Mode picker
                VStack(alignment: .leading) {
                    Text("Mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Mode", selection: Binding(
                        get: { session.lastMode },
                        set: { newMode in
                            Task { await session.changeMode(newMode, frequencyMHz: nil) }
                        }
                    )) {
                        Text("CW").tag("CW")
                        Text("LSB").tag("LSB")
                        Text("USB").tag("USB")
                        Text("AM").tag("AM")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            .padding(.horizontal)

            // Meters
            HStack(spacing: 16) {
                SDRMeterView(level: session.peakLevel, label: "Audio")
                    .frame(maxWidth: 200)
                SDRMeterView(level: Float(session.sMeter) / 127.0, label: "S-Meter")
                    .frame(maxWidth: 200)
                SDRMeterView(level: Float(session.bufferFillRatio), label: "Buffer")
                    .frame(maxWidth: 120)
            }
            .padding(.horizontal)

            // Recording info
            HStack {
                if session.recordingDuration > 0 {
                    Label(formattedDuration(session.recordingDuration), systemImage: "record.circle.fill")
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }

                Spacer()

                // Controls
                HStack(spacing: 12) {
                    Button {
                        tuneInManager.toggleMute()
                    } label: {
                        Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .help(session.isMuted ? "Unmute" : "Mute")

                    Button {
                        tuneInManager.addClipBookmark()
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .help("Add Bookmark")

                    Button {
                        Task { await tuneInManager.stop() }
                    } label: {
                        Label("Disconnect", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.vertical)
    }

    private var inactiveView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("SDR Not Connected")
                .font(.title3)

            Text("Select a spot and use \"Tune In\" to listen\nvia a remote KiwiSDR receiver.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            Spacer()
        }
    }

    private func tuneButton(label: String, offset: Double) -> some View {
        Button(label) {
            let newFreq = tuneInManager.session.lastFrequencyMHz + (offset / 1_000)
            Task { await tuneInManager.session.retune(frequencyMHz: newFreq) }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
