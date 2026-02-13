import SwiftUI

/// Full-screen recording player with waveform scrubber, transport controls,
/// speed selector, and QSO list with bidirectional sync.
struct RecordingPlayerView: View {
    // MARK: Internal

    let recording: WebSDRRecording
    let qsos: [QSO]

    @Bindable var engine: RecordingPlaybackEngine

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal)
                .padding(.top, 8)

            waveformSection
                .padding(.horizontal)
                .padding(.top, 16)

            timeLabelsRow
                .padding(.horizontal)

            transportControls
                .padding(.top, 16)

            speedPicker
                .padding(.top, 12)

            Divider()
                .padding(.top, 16)

            qsoList
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
                Button {
                    showShareClip = true
                } label: {
                    Label("Share Clip", systemImage: "scissors")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showShareClip) {
            ShareClipSheet(
                recording: recording,
                engine: engine,
                qsos: qsos
            )
            .presentationDetents([.medium])
        }
        .task {
            await loadIfNeeded()
        }
    }

    // MARK: Private

    // MARK: - Speed Picker

    @State private var selectedRate: Float = 1.0
    @State private var showShareClip = false

    // MARK: - Helpers

    private var sortedQSOs: [QSO] {
        qsos.sorted { $0.timestamp < $1.timestamp }
    }

    private var qsoOffsets: [TimeInterval] {
        let start = recording.startedAt
        return sortedQSOs.map { $0.timestamp.timeIntervalSince(start) }
    }

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
            height: 80,
            seekable: true,
            onSeek: { time in engine.seek(to: time) },
            qsoCallsigns: sortedQSOs.map(\.callsign)
        )
    }

    // MARK: - Time Labels

    private var timeLabelsRow: some View {
        HStack {
            Text(formatUTCTime(engine.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatUTCTime(engine.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
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

    // MARK: - QSO List

    private var qsoList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(
                    Array(sortedQSOs.enumerated()), id: \.element.id
                ) { index, qso in
                    qsoRow(qso, index: index)
                        .id(qso.id)
                        .onTapGesture {
                            engine.seekToQSO(at: index)
                        }
                }
            }
            .listStyle(.plain)
            .onChange(of: engine.activeQSOIndex) { _, newIndex in
                if let idx = newIndex, idx < sortedQSOs.count {
                    withAnimation {
                        proxy.scrollTo(sortedQSOs[idx].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func qsoRow(_ qso: QSO, index: Int) -> some View {
        let isActive = index == engine.activeQSOIndex

        return HStack(spacing: 8) {
            if isActive {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else {
                Text(formatQSOTime(qso.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(qso.callsign)
                .font(.subheadline)
                .fontWeight(isActive ? .bold : .regular)

            Spacer()

            if let rst = qso.rstSent {
                Text(rst)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(qso.band)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(qso.mode)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(
            isActive ? Color.accentColor.opacity(0.1) : nil
        )
    }

    private func loadIfNeeded() async {
        guard !engine.isLoaded, let fileURL = recording.fileURL else {
            return
        }
        let timestamps = sortedQSOs.map(\.timestamp)
        try? engine.load(
            fileURL: fileURL,
            qsoTimestamps: timestamps,
            recordingStart: recording.startedAt
        )
    }

    private func formatUTCTime(_ offset: TimeInterval) -> String {
        let date = recording.startedAt.addingTimeInterval(offset)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + "z"
    }

    private func formatQSOTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + "z"
    }

    private func formatFrequency(_ kHz: Double) -> String {
        let mHz = kHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }
}
