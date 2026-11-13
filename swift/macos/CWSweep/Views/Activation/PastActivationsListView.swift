import CarrierWaveData
import Combine
import SwiftData
import SwiftUI

// MARK: - PastActivationsListView

/// Scrollable list of past logging sessions for the cold-start left column
/// and session history popover. Shows park reference, qualified indicator,
/// date, mode, and duration for each session.
struct PastActivationsListView: View {
    // MARK: Internal

    /// Called when the user right-clicks a row and selects "Activate This Park".
    var onParkSelected: ((String) -> Void)?

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .task {
            await loadSessions()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: ModelContext.didSave)
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
        ) { _ in
            Task { await loadSessions() }
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
                .frame(minWidth: 500, minHeight: 400)
        }
    }

    // MARK: Private

    @State private var sessions: [LoggingSession] = []
    @State private var selectedSession: LoggingSession?
    @Environment(\.modelContext) private var modelContext

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("No past activations")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionList: some View {
        List(sessions, id: \.id) { session in
            PastActivationRow(session: session, onParkSelected: onParkSelected)
                .contentShape(Rectangle())
                .onTapGesture { selectedSession = session }
        }
        .listStyle(.plain)
    }

    private func loadSessions() async {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { $0.qsoCount > 0 },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let fetched = (try? modelContext.fetch(descriptor)) ?? []

        // Dedup by content — CloudKit mirrors can create duplicates with
        // different UUIDs. Key on startedAt (to the second) + callsign.
        // Keep the copy with the highest qsoCount.
        var bestByKey: [String: LoggingSession] = [:]
        for session in fetched {
            let key = "\(Int(session.startedAt.timeIntervalSince1970))|\(session.myCallsign)"
            if let existing = bestByKey[key] {
                if session.qsoCount > existing.qsoCount {
                    bestByKey[key] = session
                }
            } else {
                bestByKey[key] = session
            }
        }

        sessions = bestByKey.values
            .filter { hasRealQSOs(session: $0) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Check if a session has at least one non-hidden QSO.
    private func hasRealQSOs(session: LoggingSession) -> Bool {
        let sessionId = session.id
        var qsoDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> {
                $0.loggingSessionId == sessionId && !$0.isHidden
            }
        )
        qsoDescriptor.fetchLimit = 1
        let count = (try? modelContext.fetchCount(qsoDescriptor)) ?? 0
        return count > 0
    }
}

// MARK: - PastActivationRow

private struct PastActivationRow: View {
    // MARK: Internal

    let session: LoggingSession
    var onParkSelected: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                // Primary line: title + qualified indicator
                HStack {
                    Text(primaryTitle)
                        .fontWeight(.bold)
                        .lineLimit(1)

                    Spacer()

                    qualifiedIndicator
                }

                // Secondary line: detail info
                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let parkRef = contextMenuParkReference {
                Button("Activate This Park") {
                    onParkSelected?(parkRef)
                }
            }
        }
    }

    // MARK: Private

    private static let qualifiedThreshold = 10

    private var statusColor: Color {
        switch session.status {
        case .active: .green
        case .paused: .orange
        case .completed: .secondary
        }
    }

    private var primaryTitle: String {
        if session.isRove {
            return "Rove (\(session.uniqueParkCount) parks)"
        }
        return session.parkReference ?? session.programsDisplayName
    }

    private var isQualified: Bool {
        session.qsoCount >= Self.qualifiedThreshold
    }

    private var secondaryLine: String {
        var parts: [String] = []

        if session.isRove {
            let parkRefs = session.roveStops
                .map(\.parkReference)
                .prefix(4)
                .joined(separator: ", ")
            if !parkRefs.isEmpty {
                parts.append(parkRefs)
            }
        }

        parts.append(session.mode)
        parts.append(relativeDate(session.startedAt))

        return parts.joined(separator: " · ")
    }

    /// The park reference to offer in the context menu (nil hides the menu item).
    private var contextMenuParkReference: String? {
        if session.isRove {
            return session.roveStops.first?.parkReference
        }
        return session.parkReference
    }

    private var qualifiedIndicator: some View {
        HStack(spacing: 3) {
            if isQualified {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .font(.caption.weight(.bold))
            } else {
                Image(systemName: "xmark")
                    .foregroundStyle(.red)
                    .font(.caption.weight(.bold))
            }
            Text("\(session.qsoCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isQualified ? .green : .red)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
