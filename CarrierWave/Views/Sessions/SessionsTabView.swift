import SwiftData
import SwiftUI

// MARK: - SessionsTabView

/// Top-level container for the Sessions tab.
/// Switches between idle view (sessions list) and active logger
/// based on whether a logging session is active.
struct SessionsTabView: View {
    // MARK: Internal

    let tourState: TourState
    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    var onSessionStateChange: ((Bool) -> Void)?

    @Environment(\.modelContext) var modelContext

    var body: some View {
        Group {
            if sessionManager?.hasActiveSession == true {
                LoggerContainerView(
                    tourState: tourState,
                    sessionManager: sessionManager,
                    onSessionEnd: nil
                )
            } else {
                SessionsIdleView(
                    sessionManager: $sessionManager,
                    potaClient: potaClient,
                    potaAuth: potaAuth,
                    tourState: tourState
                )
            }
        }
        .onAppear {
            if sessionManager == nil {
                sessionManager = LoggingSessionManager(modelContext: modelContext)
            }
        }
        .onChange(of: sessionManager?.hasActiveSession) { _, hasSession in
            onSessionStateChange?(hasSession ?? false)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceiveWatchStartSession)
        ) { notification in
            handleWatchStartSession(notification)
        }
    }

    // MARK: Private

    @State private var sessionManager: LoggingSessionManager?

    private func handleWatchStartSession(_ notification: Notification) {
        guard let request = notification.userInfo?["request"]
            as? WatchStartSessionRequest,
            sessionManager?.hasActiveSession != true
        else {
            return
        }
        let type = ActivationType(rawValue: request.activationType) ?? .casual
        sessionManager?.startSession(
            myCallsign: request.myCallsign,
            mode: request.mode,
            frequency: request.frequency,
            activationType: type,
            parkReference: request.parkReference
        )
    }
}
