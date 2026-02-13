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
        let parkRef = activation.parkReference
        let activationDate = activation.utcDate

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let startOfDay = utcCalendar.startOfDay(for: activationDate)
        let endOfDay = utcCalendar.date(
            byAdding: .day, value: 1, to: startOfDay
        ) ?? startOfDay

        var sessionDescriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate {
                $0.parkReference == parkRef
                    && $0.startedAt >= startOfDay
                    && $0.startedAt < endOfDay
            }
        )
        sessionDescriptor.fetchLimit = 10

        guard let sessions = try? modelContext.fetch(sessionDescriptor) else {
            return
        }
        let sessionIds = sessions.map(\.id)

        let recordings = (try? WebSDRRecording.findRecordings(
            forSessionIds: sessionIds, in: modelContext
        )) ?? []

        recording = recordings.first
    }
}
