import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionsSidebarRoot

/// Sidebar root for the Sessions item.
///
/// Three-state dispatch, no modals:
/// - active session → live logger (`CustomLayoutView` or
///   `ContestSessionContainer`)
/// - pending intent → inline `SessionsComposerView`
/// - otherwise → intent grid (`SessionsLandingView`)
///
/// Mirrors the iOS `SessionsTabView` pattern but keeps everything inside the
/// sidebar pane — no sheets, no popovers — matching the CW Sweep design
/// language of dense, in-place editing.
struct SessionsSidebarRoot: View {
    // MARK: Internal

    let radioManager: RadioManager
    let flexDiscovery: FlexDiscoveryService

    var body: some View {
        Group {
            if let active = sessionManager?.activeSession,
               let contestId = active.contestId,
               !contestId.isEmpty
            {
                ContestSessionContainer(
                    session: active,
                    contestId: contestId,
                    radioManager: radioManager,
                    flexDiscovery: flexDiscovery
                )
            } else if sessionManager?.activeSession != nil {
                CustomLayoutView(radioManager: radioManager, flexDiscovery: flexDiscovery)
            } else if let sessionManager, let pendingIntent {
                SessionsComposerView(
                    intent: pendingIntent,
                    radioManager: radioManager,
                    sessionManager: sessionManager,
                    onCancel: { self.pendingIntent = nil }
                )
            } else if let sessionManager {
                SessionsLandingView(
                    pausedSessions: sessionManager.pausedSessions,
                    onResume: { sessionManager.resumeSession($0) },
                    onFinish: { sessionManager.finishSession($0) },
                    onIntent: { pendingIntent = $0 }
                )
            } else {
                ProgressView()
            }
        }
        .task {
            if sessionManager == nil {
                sessionManager = MacSessionManager(modelContext: modelContext)
            }
            sessionManager?.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didChangeLoggingSession)
        ) { _ in
            sessionManager?.refresh()
            // After a session starts the active branch takes over; clear the
            // pending intent so a future cancel returns to the landing grid.
            if sessionManager?.activeSession != nil {
                pendingIntent = nil
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var sessionManager: MacSessionManager?
    @State private var pendingIntent: SessionsIntent?
}

// MARK: - LoggingSession change notification

extension Notification.Name {
    /// Posted by `MacSessionManager` after every lifecycle mutation so the
    /// Sessions landing refreshes without polling. iOS PR5+ may start
    /// posting this too once auto-Casual lands there.
    static let didChangeLoggingSession = Notification.Name("cwDidChangeLoggingSession")
}
