import SwiftData
import SwiftUI

// MARK: - Recording Integration

extension POTAActivationDetailView {
    // MARK: Internal

    func recordingSection(_ recording: WebSDRRecording) -> some View {
        Section {
            NavigationLink {
                RecordingPlayerView(
                    recording: recording,
                    initialQSOs: activation.qsos,
                    engine: engine
                )
            } label: {
                CompactRecordingPlayer(
                    recording: recording,
                    qsos: activation.qsos,
                    engine: engine
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        }
    }

    func loadRecording() async {
        // Use session IDs from the activation's actual QSOs
        let sessionIds = Array(Set(activation.qsos.compactMap(\.loggingSessionId)))
        guard !sessionIds.isEmpty else {
            return
        }

        let recordings = (try? WebSDRRecording.findRecordings(
            forSessionIds: sessionIds, in: modelContext
        )) ?? []

        // A logging session can span multiple UTC days, so verify the
        // recording's time window overlaps with this activation's QSOs
        let qsoTimestamps = activation.qsos.map(\.timestamp)
        guard let earliest = qsoTimestamps.min(),
              let latest = qsoTimestamps.max()
        else {
            return
        }

        recording = recordings.first { rec in
            let recEnd = rec.endedAt ?? rec.startedAt
            return rec.startedAt <= latest && recEnd >= earliest
        }
    }
}
