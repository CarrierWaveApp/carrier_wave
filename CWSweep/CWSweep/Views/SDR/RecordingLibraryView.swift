import CarrierWaveData
import os
import SwiftData
import SwiftUI

private let recordingLibraryLogger = Logger(subsystem: "com.jsvana.CWSweep", category: "RecordingLibrary")

// MARK: - RecordingLibraryView

/// Browse and play back SDR recordings
struct RecordingLibraryView: View {
    // MARK: Internal

    var body: some View {
        HSplitView {
            // Recording list
            Table(recordings, selection: $selectedRecordingId) {
                TableColumn("Date") { recording in
                    Text(recording.startedAt, style: .date)
                        .font(.caption)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Receiver") { recording in
                    Text(recording.kiwisdrName
                        .isEmpty ? (recording.kiwisdrHost.isEmpty ? "—" : recording.kiwisdrHost) : recording
                        .kiwisdrName)
                        .font(.caption)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 120)

                TableColumn("Frequency") { recording in
                    Text(String(format: "%.1f kHz", recording.frequencyKHz))
                        .font(.caption.monospacedDigit())
                }
                .width(min: 60, ideal: 80)

                TableColumn("Mode") { recording in
                    Text(recording.mode)
                        .font(.caption)
                }
                .width(min: 30, ideal: 40)

                TableColumn("Duration") { recording in
                    Text(formattedDuration(recording.durationSeconds))
                        .font(.caption.monospacedDigit())
                }
                .width(min: 50, ideal: 60)

                TableColumn("Size") { recording in
                    Text(formattedSize(recording.fileSizeBytes))
                        .font(.caption)
                }
                .width(min: 40, ideal: 50)
            }
            .frame(minWidth: 300, maxHeight: .infinity)
            .onChange(of: selectedRecordingId) { _, _ in
                loadRecording(selectedRecording)
            }

            // Player panel
            VStack {
                if let recording = selectedRecording {
                    RecordingPlayerView(
                        recording: recording,
                        playbackEngine: playbackEngine
                    )
                } else {
                    ContentUnavailableView(
                        "Select a Recording",
                        systemImage: "waveform",
                        description: Text("Choose a recording from the list to play it back.")
                    )
                }
            }
            .frame(minWidth: 300, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private

    @Query(sort: \WebSDRRecording.startedAt, order: .reverse) private var recordings: [WebSDRRecording]
    @State private var selectedRecordingId: UUID?
    @State private var playbackEngine = RecordingPlaybackEngine()
    @Environment(\.modelContext) private var modelContext

    private var selectedRecording: WebSDRRecording? {
        guard let id = selectedRecordingId else {
            return nil
        }
        return recordings.first { $0.id == id }
    }

    private func loadRecording(_ recording: WebSDRRecording?) {
        playbackEngine.stop()
        guard let recording,
              let fileURL = recording.fileURL
        else {
            return
        }

        do {
            try playbackEngine.load(
                fileURL: fileURL,
                qsoTimestamps: [],
                recordingStart: recording.startedAt,
                segments: recording.segments
            )
            playbackEngine.loadTranscript(sessionId: recording.loggingSessionId)
        } catch {
            recordingLibraryLogger.error("Load failed: \(error.localizedDescription)")
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        if bytes > 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        }
        return String(format: "%.0f KB", Double(bytes) / 1_000)
    }
}
