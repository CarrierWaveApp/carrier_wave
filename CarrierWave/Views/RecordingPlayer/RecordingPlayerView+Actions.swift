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
