import SwiftData
import SwiftUI

/// Lists all completed logging sessions grouped by month.
/// Sessions with WebSDR recordings show a recording badge.
struct SessionsView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
        .task {
            await loadSessions()
            await loadRecordings()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var sessions: [LoggingSession] = []
    @State private var recordingsBySessionId: [UUID: WebSDRRecording] = [:]
    @State private var engines: [UUID: RecordingPlaybackEngine] = [:]

    private var sessionsByMonth: [(month: String, sessions: [LoggingSession])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")

        let grouped = Dictionary(grouping: sessions) { session in
            formatter.string(from: session.startedAt)
        }

        return grouped
            .sorted { $0.value[0].startedAt > $1.value[0].startedAt }
            .map { (month: $0.key, sessions: $0.value) }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Sessions",
            systemImage: "clock",
            description: Text(
                "Completed logging sessions will appear here."
            )
        )
    }

    private var sessionsList: some View {
        List {
            ForEach(sessionsByMonth, id: \.month) { group in
                Section(group.month) {
                    ForEach(group.sessions, id: \.id) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: LoggingSession) -> some View {
        let recording = recordingsBySessionId[session.id]

        return NavigationLink {
            if let recording {
                RecordingPlayerView(
                    recording: recording,
                    engine: engineFor(session.id)
                )
            } else {
                SessionDetailView(session: session)
            }
        } label: {
            sessionRowLabel(session, hasRecording: recording != nil)
        }
    }

    private func sessionRowLabel(
        _ session: LoggingSession, hasRecording: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: session.activationType.icon)
                    .foregroundStyle(.secondary)
                Text(session.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(session.startedAt.formatted(
                    date: .abbreviated, time: .omitted
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(
                    "\(session.qsoCount) QSO\(session.qsoCount == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(session.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hasRecording {
                    Label("Recording", systemImage: "waveform.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if !session.photoFilenames.isEmpty {
                    Label(
                        "\(session.photoFilenames.count)",
                        systemImage: "photo"
                    )
                    .font(.caption2)
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func engineFor(_ sessionId: UUID) -> RecordingPlaybackEngine {
        if let existing = engines[sessionId] {
            return existing
        }
        let engine = RecordingPlaybackEngine()
        engines[sessionId] = engine
        return engine
    }

    private func loadSessions() async {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "completed" },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200

        sessions = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func loadRecordings() async {
        let sessionIds = sessions.map(\.id)
        guard !sessionIds.isEmpty else {
            return
        }

        let recordings = (try? WebSDRRecording.findRecordings(
            forSessionIds: sessionIds, in: modelContext
        )) ?? []

        var dict: [UUID: WebSDRRecording] = [:]
        for recording in recordings {
            dict[recording.loggingSessionId] = recording
        }
        recordingsBySessionId = dict
    }
}
