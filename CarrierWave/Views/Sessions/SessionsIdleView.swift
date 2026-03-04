import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionsIdleView

/// Shown when no session is active. Displays active/paused sessions
/// at the top and completed sessions (via SessionsView) below.
struct SessionsIdleView: View {
    // MARK: Internal

    @Binding var sessionManager: LoggingSessionManager?
    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let tourState: TourState

    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationStack {
            SessionsView(
                potaClient: potaClient,
                potaAuth: potaAuth,
                tourState: tourState,
                isEmbedded: true,
                activeSessionsHeader: activeSessions.isEmpty
                    ? nil
                    : { AnyView(activeSessionsHeader) }
            )
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if tourState.shouldShowMiniTour(.loggerInteractive) {
                            let manager = LoggerTourManager()
                            manager.setOnComplete {
                                tourState.markMiniTourSeen(.loggerInteractive)
                                tourState.markMiniTourSeen(.logger)
                                loggerTourManager = nil
                            }
                            manager.start()
                            loggerTourManager = manager
                        } else {
                            showSessionSheet = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New session")
                }
            }
            .sheet(isPresented: $showSessionSheet) {
                SessionStartSheet(
                    sessionManager: sessionManager,
                    onDismiss: { showSessionSheet = false }
                )
            }
            .fullScreenCover(item: $loggerTourManager) { manager in
                LoggerTourOverlay(tourManager: manager)
            }
            .finishSessionDialog(
                session: $sessionToFinish,
                sessionManager: sessionManager,
                onRefresh: { refreshActiveSessions() }
            )
            .deleteSessionDialog(
                session: $sessionToDelete,
                qsoCounts: activeSessionQSOCounts,
                sessionManager: sessionManager,
                onRefresh: { refreshActiveSessions() }
            )
        }
        .task {
            refreshActiveSessions()
        }
    }

    // MARK: Private

    @State private var activeSessions: [LoggingSession] = []
    @State private var activeSessionQSOCounts: [UUID: Int] = [:]
    @State private var sessionToFinish: LoggingSession?
    @State private var sessionToDelete: LoggingSession?
    @State private var showSessionSheet = false
    @State private var loggerTourManager: LoggerTourManager?

    // MARK: - Active Sessions Header

    @ViewBuilder
    private var activeSessionsHeader: some View {
        if !activeSessions.isEmpty {
            Section {
                ForEach(activeSessions, id: \.id) { session in
                    ActiveSessionRow(
                        session: session,
                        qsoCount: activeSessionQSOCounts[session.id] ?? 0,
                        onContinue: {
                            sessionManager?.resumeSession(session)
                        },
                        onPause: {
                            sessionManager?.pauseOtherSession(session)
                            refreshActiveSessions()
                        },
                        onFinish: {
                            sessionToFinish = session
                        },
                        onDelete: {
                            sessionToDelete = session
                        }
                    )
                }
            } header: {
                Text("Active Sessions")
            }
        }
    }

    // MARK: - Data

    private func refreshActiveSessions() {
        guard let manager = sessionManager else {
            activeSessions = []
            activeSessionQSOCounts = [:]
            return
        }

        activeSessions = manager.fetchActiveSessions()

        var counts: [UUID: Int] = [:]
        for session in activeSessions {
            let sessionId = session.id
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.loggingSessionId == sessionId && !$0.isHidden }
            )
            descriptor.fetchLimit = 500
            counts[sessionId] = (try? modelContext.fetch(descriptor))?.count ?? 0
        }
        activeSessionQSOCounts = counts
    }
}

// MARK: - Confirmation Dialog Modifiers

extension View {
    func finishSessionDialog(
        session: Binding<LoggingSession?>,
        sessionManager: LoggingSessionManager?,
        onRefresh: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Finish Session",
            isPresented: Binding(
                get: { session.wrappedValue != nil },
                set: { newValue in
                    if !newValue {
                        session.wrappedValue = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Finish Session") {
                if let sess = session.wrappedValue {
                    sessionManager?.finishSession(sess)
                    onRefresh()
                }
            }
            Button("Cancel", role: .cancel) {
                session.wrappedValue = nil
            }
        } message: {
            if let sess = session.wrappedValue {
                Text(
                    "Finish \"\(sess.displayTitle)\"? "
                        + "It will move to your Sessions list."
                )
            }
        }
    }

    func deleteSessionDialog(
        session: Binding<LoggingSession?>,
        qsoCounts: [UUID: Int],
        sessionManager: LoggingSessionManager?,
        onRefresh: @escaping () -> Void
    ) -> some View {
        alert(
            "Delete Session",
            isPresented: Binding(
                get: { session.wrappedValue != nil },
                set: { newValue in
                    if !newValue {
                        session.wrappedValue = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let sess = session.wrappedValue {
                    sessionManager?.deleteSession(sess)
                    onRefresh()
                }
                session.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) {
                session.wrappedValue = nil
            }
        } message: {
            if let sess = session.wrappedValue {
                let count = qsoCounts[sess.id] ?? 0
                Text(
                    "Delete \"\(sess.displayTitle)\" and hide "
                        + "\(count) QSO(s)? Hidden QSOs will not be "
                        + "synced or counted in statistics."
                )
            }
        }
    }
}
