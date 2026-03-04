import CarrierWaveData
import SwiftUI

// MARK: - TranscriptViewMode

/// Display mode for the transcript area
enum TranscriptViewMode: String, CaseIterable {
    case chat = "Chat"
    case raw = "Raw"
}

// MARK: - CWTranscriptionView

/// Main CW transcription view with audio visualization and decoded transcript.
struct CWTranscriptionView: View {
    // MARK: Internal

    /// Whether the view is presented modally (shows Close button)
    var isModal: Bool = false

    /// Optional callback when user wants to log a QSO
    var onLog: ((String) -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                statusBar
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Level meter
                CWLevelMeter(
                    level: service.isListening ? Double(service.peakAmplitude) : 0,
                    isActive: service.isKeyDown
                )
                .padding(.horizontal)

                // Noise floor indicator
                noiseFloorSection
                    .padding(.horizontal)
                    .padding(.bottom)

                // Transcript area
                transcriptArea
                    .padding(.horizontal)

                // Detected callsign bar
                if service.detectedCallsign != nil {
                    CWDetectedCallsignBar(
                        callsign: service.detectedCallsign,
                        allCallsigns: service.detectedCallsigns,
                        onUse: { callsign in
                            onLog?(callsign)
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                Spacer()

                // Control buttons
                controlBar
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("CW Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            service.stopListening()
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        CWSettingsMenu(service: service)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    // MARK: Private

    @State private var service = CWTranscriptionService()
    @Environment(\.dismiss) private var dismiss
    @State private var viewMode: TranscriptViewMode = .chat

    private var statusColor: Color {
        switch service.state {
        case .idle:
            .secondary
        case .listening:
            if service.isCalibrating {
                .orange
            } else if service.isNoiseTooHigh {
                .yellow
            } else {
                .green
            }
        case .error:
            .red
        }
    }

    private var statusText: String {
        switch service.state {
        case .idle:
            "Ready"
        case .listening:
            if service.isCalibrating {
                "Calibrating..."
            } else if service.isNoiseTooHigh {
                "High Noise"
            } else {
                "Listening"
            }
        case let .error(message):
            message
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 12) {
            // Status indicator row
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)

                    Text(statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(statusColor)
                }

                Spacer()
            }

            // Settings controls
            settingsControls
        }
    }

    // MARK: - Settings Controls

    private var settingsControls: some View {
        HStack(spacing: 12) {
            // WPM box
            CWSpeedBox(wpm: service.estimatedWPM) {
                // Cycle through common WPM values
                let presets = [15, 20, 25, 30]
                if let currentIndex = presets.firstIndex(of: service.estimatedWPM) {
                    let nextIndex = (currentIndex + 1) % presets.count
                    service.setWPM(presets[nextIndex])
                } else {
                    service.setWPM(20)
                }
            }

            // Frequency meter
            VStack(spacing: 4) {
                CWFrequencyMeter(
                    centerFrequency: 600,
                    detectedFrequency: service.detectedFrequency,
                    frequencyRange: 200,
                    isListening: service.isListening
                )

                // Auto/Fixed indicator with detected frequency
                HStack(spacing: 4) {
                    if service.adaptiveFrequencyEnabled {
                        Image(systemName: "a.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        if let detected = service.detectedFrequency {
                            Text("\(Int(detected)) Hz")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Fixed: \(Int(service.toneFrequency)) Hz")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Pre-amp toggle
            Button {
                service.preAmpEnabled.toggle()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.title3)
                    Text("PRE")
                        .font(.caption2.weight(.medium))
                }
                .frame(width: 56, height: 56)
                .background(service.preAmpEnabled ? Color.orange : Color(.systemGray5))
                .foregroundStyle(service.preAmpEnabled ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Noise Floor Section

    private var noiseFloorSection: some View {
        CWNoiseFloorIndicator(
            noiseFloor: service.noiseFloor,
            quality: service.noiseFloorQuality,
            isListening: service.isListening
        )
    }

    // MARK: - Transcript Area

    private var transcriptArea: some View {
        VStack(spacing: 8) {
            // View mode picker
            Picker("View Mode", selection: $viewMode) {
                ForEach(TranscriptViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Conditional view based on mode
            if service.transcript.isEmpty, service.currentLine.isEmpty, service.conversation.isEmpty {
                CWEmptyTranscriptView(isListening: service.isListening)
                    .frame(minHeight: 200)
            } else {
                switch viewMode {
                case .chat:
                    CWChatView(
                        conversation: service.conversation,
                        callsignLookup: nil // Will be connected to lookup service later
                    )
                    .frame(minHeight: 200)

                case .raw:
                    CWTranscriptView(
                        entries: service.transcript,
                        currentLine: service.currentLine
                    )
                    .frame(minHeight: 200)
                }
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 16) {
            // Action buttons
            HStack(spacing: 16) {
                // Copy button
                Button {
                    let text = service.copyTranscript()
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(service.transcript.isEmpty && service.currentLine.isEmpty)

                // Clear button
                Button {
                    service.clearTranscript()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(service.transcript.isEmpty && service.currentLine.isEmpty)

                Spacer()

                // Main start/stop button
                Button {
                    if service.isListening {
                        service.stopListening()
                    } else {
                        Task {
                            await service.startListening()
                        }
                    }
                } label: {
                    Label(
                        service.isListening ? "Stop" : "Start",
                        systemImage: service.isListening ? "stop.fill" : "mic.fill"
                    )
                    .font(.headline)
                    .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(service.isListening ? .red : .green)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CWTranscriptionView()
}
