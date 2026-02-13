import SwiftUI

// MARK: - ShareClipSheet

/// Sheet for selecting a time range and exporting a clip
struct ShareClipSheet: View {
    // MARK: Internal

    let recording: WebSDRRecording
    let engine: RecordingPlaybackEngine
    let qsos: [QSO]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Select clip range")
                    .font(.headline)

                RecordingWaveformView(
                    amplitudes: engine.amplitudeEnvelope,
                    duration: engine.duration,
                    currentTime: engine.currentTime,
                    qsoOffsets: [],
                    activeQSOIndex: nil,
                    height: 60,
                    seekable: false
                )
                .overlay {
                    rangeOverlay
                }
                .padding(.horizontal)

                HStack {
                    Text(formatTime(rangeStart))
                    Spacer()
                    Text(formatTime(rangeEnd))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                durationLabel

                if let error = exportError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                exportButton
            }
            .padding()
            .navigationTitle("Share Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { setDefaultRange() }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var rangeStart: TimeInterval = 0
    @State private var rangeEnd: TimeInterval = 0
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var exportError: String?

    @ViewBuilder
    private var exportButton: some View {
        if let url = exportedURL {
            ShareLink(item: url) {
                Label("Share Clip", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                Task { await exportClip() }
            } label: {
                if isExporting {
                    ProgressView()
                } else {
                    Label("Export Clip", systemImage: "scissors")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)
        }
    }

    private var rangeOverlay: some View {
        GeometryReader { geo in
            let startX = xPos(rangeStart, in: geo.size.width)
            let endX = xPos(rangeEnd, in: geo.size.width)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: startX)
                Spacer()
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: geo.size.width - endX)
            }
        }
    }

    private var durationLabel: some View {
        let clipDuration = rangeEnd - rangeStart
        return Text("Clip: \(formatTime(clipDuration))")
            .font(.subheadline)
    }

    private func setDefaultRange() {
        if let activeIdx = engine.activeQSOIndex {
            let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
            if activeIdx < sorted.count {
                let offset = sorted[activeIdx].timestamp
                    .timeIntervalSince(recording.startedAt)
                rangeStart = max(0, offset - 90)
                rangeEnd = min(engine.duration, offset + 15)
                return
            }
        }
        rangeStart = 0
        rangeEnd = min(60, engine.duration)
    }

    private func exportClip() async {
        guard let fileURL = recording.fileURL else {
            return
        }
        isExporting = true
        exportError = nil

        do {
            let url = try await RecordingClipExporter.exportClip(
                sourceURL: fileURL,
                startTime: rangeStart,
                endTime: rangeEnd
            )
            exportedURL = url
        } catch {
            exportError = error.localizedDescription
        }

        isExporting = false
    }

    private func xPos(_ time: TimeInterval, in width: CGFloat) -> CGFloat {
        guard engine.duration > 0 else {
            return 0
        }
        return CGFloat(time / engine.duration) * width
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
