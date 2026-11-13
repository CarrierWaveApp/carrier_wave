import CarrierWaveData
import SwiftUI

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
