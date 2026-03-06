import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionsListView

/// List of logging sessions with start/pause/end controls and detail split view
struct SessionsListView: View {
    // MARK: Internal

    var body: some View {
        HSplitView {
            // Left pane: session list
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Sessions")
                        .font(.headline)
                    Spacer()
                    Button {
                        showNewSession = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Start new session")
                    .help("Start New Session")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

            // Right pane: detail or empty state
            if let session = selectedSession {
                SessionDetailView(session: session)
            } else {
                detailEmptyState
            }
        }
        .task {
            await loadSessions()
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionSheet { session in
                modelContext.insert(session)
                sessions.insert(session, at: 0)
            }
        }
    }

    // MARK: Private

    @State private var sessions: [LoggingSession] = []
    @State private var selectedSessionID: UUID?
    @State private var showNewSession = false
    @Environment(\.modelContext) private var modelContext

    private var selectedSession: LoggingSession? {
        guard let id = selectedSessionID else {
            return nil
        }
        return sessions.first { $0.id == id }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("No sessions yet")
                .foregroundStyle(.secondary)
            Button("Start Session") {
                showNewSession = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var detailEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("Select a session")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Choose a session from the list to view details")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionList: some View {
        List(sessions, selection: $selectedSessionID) { session in
            SessionRow(session: session) {
                await loadSessions()
            }
            .tag(session.id)
        }
    }

    private func loadSessions() async {
        let descriptor = FetchDescriptor<LoggingSession>(
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        sessions = fetched.filter { $0.qsoCount > 0 }
    }
}

// MARK: - SessionRow

struct SessionRow: View {
    // MARK: Internal

    let session: LoggingSession
    let onUpdate: () async -> Void

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.customTitle ?? session.programsDisplayName)
                        .fontWeight(.medium)
                    if let park = session.parkReference {
                        Text(park)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                HStack(spacing: 8) {
                    Text(session.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(session.qsoCount) QSOs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Session controls
            if session.isActive {
                Button {
                    session.pause()
                    Task { await onUpdate() }
                } label: {
                    Image(systemName: "pause.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Pause session")

                Button {
                    session.end()
                    Task { await onUpdate() }
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("End session")
            } else if session.status == .paused {
                Button {
                    session.resume()
                    Task { await onUpdate() }
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Resume session")

                Button {
                    session.end()
                    Task { await onUpdate() }
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("End session")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var statusColor: Color {
        switch session.status {
        case .active: .green
        case .paused: .orange
        case .completed: .secondary
        }
    }

    private var formattedDuration: String {
        let interval = session.duration
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - NewSessionSheet

struct NewSessionSheet: View {
    // MARK: Internal

    let onCreate: (LoggingSession) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("New Session")
                .font(.headline)
                .padding()

            Form {
                Picker("Type", selection: $activationType) {
                    ForEach(ActivationType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }

                if activationType == .pota {
                    TextField("Park Reference (e.g., K-1234)", text: $parkReference)
                }

                Picker("Mode", selection: $mode) {
                    Text("CW").tag("CW")
                    Text("SSB").tag("SSB")
                    Text("FT8").tag("FT8")
                    Text("FT4").tag("FT4")
                    Text("RTTY").tag("RTTY")
                    Text("AM").tag("AM")
                    Text("FM").tag("FM")
                }
                TextField("Power (watts)", text: $power)
                    .onSubmit {} // Allow keyboard entry
                TextField("Notes", text: $notes)
            }
            .formStyle(.grouped)
            .frame(width: 400)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Start Session") {
                    let session = LoggingSession(
                        myCallsign: currentCallsign,
                        mode: mode,
                        activationType: activationType,
                        parkReference: parkReference.isEmpty ? nil : parkReference.uppercased(),
                        notes: notes.isEmpty ? nil : notes,
                        power: Int(power)
                    )
                    onCreate(session)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var activationType: ActivationType = .casual
    @State private var parkReference = ""
    @State private var mode = "CW"
    @State private var power = ""
    @State private var notes = ""
    @State private var myCallsign = ""

    private var currentCallsign: String {
        (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign)) ?? ""
    }
}
