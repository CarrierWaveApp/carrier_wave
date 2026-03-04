import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - WebSDRRecordingsView

/// List of all WebSDR recordings with delete, share, and details.
struct WebSDRRecordingsView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if recordings.isEmpty {
                emptyState
            } else {
                recordingsList
            }
        }
        .navigationTitle("WebSDR Recordings")
        .task {
            await loadRecordings()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var recordings: [WebSDRRecording] = []

    private var emptyState: some View {
        ContentUnavailableView(
            "No Recordings",
            systemImage: "waveform.circle",
            description: Text(
                "WebSDR recordings from your logging sessions will appear here."
            )
        )
    }

    private var recordingsList: some View {
        List {
            ForEach(recordings, id: \.id) { recording in
                recordingRow(recording)
            }
            .onDelete { indexSet in
                deleteRecordings(at: indexSet)
            }
        }
    }

    private func recordingRow(_ recording: WebSDRRecording) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                recordingCallsignHeader(recording)
                recordingLocationBadge(recording)
                recordingFrequencyRow(recording)
                recordingDetailsRow(recording)
            }
            Spacer()
            if let fileURL = recording.fileURL {
                ShareLink(item: fileURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func recordingCallsignHeader(
        _ recording: WebSDRRecording
    ) -> some View {
        if let callsign = recording.spotCallsign {
            HStack(spacing: 6) {
                Text(callsign)
                    .font(.subheadline.weight(.semibold).monospaced())
                if recording.isTuneInRecording {
                    Text("TUNE IN")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.cyan.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        } else {
            Text(recording.kiwisdrName)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private func recordingLocationBadge(
        _ recording: WebSDRRecording
    ) -> some View {
        if let parkRef = recording.spotParkRef {
            HStack(spacing: 4) {
                Image(systemName: "tree.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(parkRef)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let parkName = recording.spotParkName {
                    Text(parkName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else if let summit = recording.spotSummitCode {
            HStack(spacing: 4) {
                Image(systemName: "mountain.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.brown)
                Text(summit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recordingFrequencyRow(
        _ recording: WebSDRRecording
    ) -> some View {
        HStack(spacing: 8) {
            Text(formatFrequency(recording.frequencyKHz))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(recording.mode)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let band = recording.spotBand {
                Text(band)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recordingDetailsRow(
        _ recording: WebSDRRecording
    ) -> some View {
        HStack(spacing: 8) {
            Text(recording.startedAt.formatted(
                date: .abbreviated,
                time: .shortened
            ))
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Text(recording.formattedDuration)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if recording.fileSizeBytes > 0 {
                Text(recording.formattedFileSize)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            let clips = recording.clipBookmarks.count
            if clips > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                    Text("\(clips)")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
            }
        }
    }

    private func formatFrequency(_ kHz: Double) -> String {
        let mHz = kHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }

    private func loadRecordings() async {
        var descriptor = FetchDescriptor<WebSDRRecording>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100

        recordings = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]
            recording.deleteFile()
            modelContext.delete(recording)
        }
        try? modelContext.save()
        recordings.remove(atOffsets: offsets)
    }
}
