import SwiftData
import SwiftUI

/// Full-screen recording player with waveform scrubber, transport controls,
/// speed selector, transcript panel, and collapsible QSO list.
struct RecordingPlayerView: View {
    // MARK: Internal

    let recording: WebSDRRecording
    var initialQSOs: [QSO] = []

    @Bindable var engine: RecordingPlaybackEngine

    // State accessible from extension
    @Environment(\.modelContext) var modelContext
    @State var selectedRate: Float = 1.0
    @State var showShareClip = false
    @State var loadedQSOs: [QSO]?
    @State var isQSOListExpanded = false
    @State var isTranscribing = false
    @State var transcriptionProgress: Float = 0
    @State var transcriptionError: String?
    @AppStorage("cwswlServerURL") var cwswlServerURL = "http://192.168.1.94:8080"

    // MARK: - Helpers

    var effectiveQSOs: [QSO] {
        loadedQSOs ?? (initialQSOs.isEmpty ? [] : initialQSOs)
    }

    var sortedQSOs: [QSO] {
        effectiveQSOs.sorted { $0.timestamp < $1.timestamp }
    }

    var qsoOffsets: [TimeInterval] {
        let start = recording.startedAt
        return sortedQSOs.map { $0.timestamp.timeIntervalSince(start) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal)
                .padding(.top, 8)

            waveformSection
                .padding(.horizontal)
                .padding(.top, 12)

            timeLabelsRow
                .padding(.horizontal)

            transportControls
                .padding(.top, 12)

            speedPicker
                .padding(.top, 8)

            Divider()
                .padding(.top, 12)

            // Transcript takes primary space
            transcriptSection
                .frame(maxHeight: .infinity)

            Divider()

            // Collapsible QSO summary at bottom
            qsoSummarySection
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showShareClip) {
            ShareClipSheet(
                recording: recording,
                engine: engine,
                qsos: effectiveQSOs
            )
            .landscapeAdaptiveDetents(portrait: [.medium])
        }
        .task {
            await loadQSOs()
            await loadIfNeeded()
        }
    }

    // MARK: Private

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.kiwisdrName)
                .font(.headline)
            HStack(spacing: 8) {
                Text(formatFrequency(recording.frequencyKHz))
                Text(recording.mode)
                Text(recording.startedAt.formatted(
                    date: .abbreviated, time: .shortened
                ))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        RecordingWaveformView(
            amplitudes: engine.amplitudeEnvelope,
            duration: engine.duration,
            currentTime: engine.currentTime,
            qsoOffsets: qsoOffsets,
            activeQSOIndex: engine.activeQSOIndex,
            height: 60,
            seekable: true,
            onSeek: { time in engine.seek(to: time) },
            qsoCallsigns: sortedQSOs.map(\.callsign),
            qsoRanges: engine.qsoRanges,
            segments: engine.segments
        )
    }

    // MARK: - Time Labels

    private var timeLabelsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatOffset(engine.currentTime))
                    .font(.caption.monospacedDigit())
                Text(formatUTCTime(engine.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatOffset(engine.duration))
                    .font(.caption.monospacedDigit())
                Text(formatUTCTime(engine.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack(spacing: 24) {
            Button { engine.previousQSO() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
            }

            Button { engine.skip(by: -15) } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
            }

            Button { engine.togglePlayPause() } label: {
                Image(
                    systemName: engine.isPlaying
                        ? "pause.circle.fill" : "play.circle.fill"
                )
                .font(.largeTitle)
            }

            Button { engine.skip(by: 15) } label: {
                Image(systemName: "goforward.15")
                    .font(.title2)
            }

            Button { engine.nextQSO() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
            }
        }
        .buttonStyle(.borderless)
    }

    private var speedPicker: some View {
        HStack(spacing: 0) {
            ForEach([Float(0.5), 1.0, 1.5, 2.0], id: \.self) { rate in
                Button {
                    selectedRate = rate
                    engine.playbackRate = rate
                } label: {
                    Text(rate == 1.0 ? "1x" : String(format: "%.1fx", rate))
                        .font(.caption)
                        .fontWeight(selectedRate == rate ? .bold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedRate == rate
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(spacing: 0) {
            if isTranscribing {
                transcriptionProgressView
            } else if let error = transcriptionError {
                transcriptionErrorView(error)
            } else {
                RecordingTranscriptView(
                    transcript: engine.transcript,
                    segments: engine.segments,
                    activeLineIndex: engine.activeTranscriptLineIndex,
                    activeWordIndex: engine.activeTranscriptWordIndex,
                    currentTime: engine.currentTime,
                    recordingStartedAt: recording.startedAt,
                    onSeek: { time in engine.seek(to: time) },
                    onTranscribe: cwswlServerURL.isEmpty ? nil : {
                        Task { await startTranscription() }
                    }
                )
            }
        }
    }

    private var transcriptionProgressView: some View {
        VStack(spacing: 12) {
            ProgressView(value: transcriptionProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 200)
            Text("Transcribing... \(Int(transcriptionProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button {
                showShareClip = true
            } label: {
                Label("Share Clip", systemImage: "scissors")
            }
            .buttonStyle(.bordered)

            if engine.transcript != nil, !cwswlServerURL.isEmpty {
                Button {
                    Task { await startTranscription() }
                } label: {
                    Label("Retranscribe", systemImage: "arrow.trianglehead.2.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isTranscribing)
            }
        }
        .padding()
        .background(.bar)
    }
}
