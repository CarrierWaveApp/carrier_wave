import AVFoundation
import CarrierWaveData
import SwiftUI

// MARK: - ShareClipSheet

/// Sheet for selecting a time range from a recording and exporting/sharing a clip.
/// Features draggable range handles, QSO markers, segment boundaries,
/// playback preview, transcript snippet, and branded share card.
struct ShareClipSheet: View {
    // MARK: Internal

    let recording: WebSDRRecording
    let engine: RecordingPlaybackEngine
    let qsos: [QSO]

    @State var rangeStart: TimeInterval = 0
    @State var rangeEnd: TimeInterval = 0
    @State var isDraggingStart = false
    @State var isDraggingEnd = false
    @State var isExporting = false
    @State var isPreviewing = false
    @State var exportedURL: URL?
    @State var exportError: String?
    @State var isRenderingCard = false
    @State var shareCardData: RecordingShareCardData?

    var sortedQSOs: [QSO] {
        qsos.sorted { $0.timestamp < $1.timestamp }
    }

    var qsoOffsets: [TimeInterval] {
        let start = recording.startedAt
        return sortedQSOs.map { $0.timestamp.timeIntervalSince(start) }
    }

    var clipDuration: TimeInterval {
        rangeEnd - rangeStart
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    waveformWithHandles
                    timeLabels
                    durationLabel

                    if engine.transcript != nil {
                        transcriptSnippet
                    }

                    if let error = exportError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    previewControls
                    exportActions
                }
                .padding()
            }
            .navigationTitle("Share Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { setDefaultRange() }
            .sheet(item: $shareCardData) { data in
                RecordingSharePreviewSheet(data: data) {
                    shareCardData = nil
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}

// MARK: - RecordingPlayerView + Recording Export

extension RecordingPlayerView {
    func exportRecording() async {
        guard let sourceURL = recording.fileURL else {
            return
        }
        isExportingRecording = true
        defer { isExportingRecording = false }

        do {
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration)
            let totalSeconds = CMTimeGetSeconds(duration)

            let dateStr = recording.startedAt.formatted(
                .iso8601.year().month().day().dateSeparator(.dash)
            )
            let freqMHz = recording.frequencyKHz / 1_000
            let freqStr = freqMHz == freqMHz.rounded()
                ? String(format: "%.0fMHz", freqMHz)
                : String(format: "%.3fMHz", freqMHz)
            let fileName = "\(recording.kiwisdrName) \(freqStr) \(recording.mode) \(dateStr)"

            let url = try await RecordingClipExporter.exportClip(
                sourceURL: sourceURL,
                startTime: 0,
                endTime: totalSeconds,
                metadata: RecordingClipMetadata(
                    receiverName: recording.kiwisdrName,
                    frequencyKHz: recording.frequencyKHz,
                    mode: recording.mode,
                    recordingDate: recording.startedAt,
                    callsigns: sortedQSOs.map(\.callsign)
                ),
                outputFileName: fileName
            )
            exportedRecordingURL = url
            showShareRecording = true
        } catch {
            // Silently fail — user can retry
        }
    }
}

// MARK: - RecordingShareSheet

/// UIActivityViewController wrapper for sharing a recording file
struct RecordingShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
