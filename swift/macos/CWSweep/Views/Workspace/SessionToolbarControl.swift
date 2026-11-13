import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionToolbarControl

/// Toolbar control for the active logging session.
///
/// Sits next to `LayoutPicker` in the workspace toolbar when the Logger
/// sidebar item is selected. When a session is active it surfaces End and
/// Pause actions — previously the only way to stop a session was to navigate
/// back to the Sessions landing strip.
///
/// The manager is owned by `WorkspaceView` so the same instance backs the
/// command palette's End/Pause commands.
struct SessionToolbarControl: View {
    // MARK: Internal

    let sessionManager: MacSessionManager

    var body: some View {
        if let session = sessionManager.activeSession {
            Menu {
                Button("End Session", systemImage: "stop.circle") {
                    sessionManager.finishSession(session)
                }
                Button("Pause Session", systemImage: "pause.circle") {
                    sessionManager.pauseSession()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                    Text(label(for: session))
                        .font(.callout)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.bar, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Active session — End or Pause")
        }
    }

    // MARK: Private

    private func label(for session: LoggingSession) -> String {
        if let park = session.parkReference, !park.isEmpty {
            return park
        }
        if let sota = session.sotaReference, !sota.isEmpty {
            return sota
        }
        if let wwff = session.wwffReference, !wwff.isEmpty {
            return wwff
        }
        if let contestId = session.contestId, !contestId.isEmpty {
            return contestId.uppercased()
        }
        return session.myCallsign
    }
}
