import CarrierWaveData
import SwiftUI

// MARK: - Session Row Construction & Session Actions

extension SessionsView {
    func reopenSession() {
        guard let session = sessionToReopen else {
            return
        }
        sessionToReopen = nil
        sessionManager?.reopenSession(session)
    }

    /// Reopen a specific session directly, bypassing the parent-level
    /// confirmation flow. Used by `SessionDetailView`, which presents its
    /// own confirmation locally so the dialog appears while the detail view
    /// is on top of the navigation stack (CAR-250).
    func performReopen(_ session: LoggingSession) {
        sessionManager?.reopenSession(session)
    }

    func mergeSession(
        _ source: LoggingSession,
        into target: LoggingSession
    ) {
        sessionToMerge = nil
        sessionManager?.mergeSessions(source: source, into: target)
        Task {
            await loadSessions()
            await loadOrphanActivations()
        }
    }

    func buildSessionRow(_ session: LoggingSession) -> SessionRow {
        let activations = activationsBySessionId[session.id] ?? []
        let primaryActivation = activations.first
        let qsos = qsosBySessionId[session.id] ?? []
        let meta = primaryActivation.flatMap { activationMetadata(for: $0) }
        let sessionJobs = activations.flatMap {
            jobsByActivationId[$0.id] ?? []
        }

        return SessionRow(
            session: session,
            qsos: qsos,
            activations: activations,
            metadata: meta,
            parkName: primaryActivation.flatMap { parkName(for: $0.parkReference) },
            hasRecording: recordingsBySessionId[session.id] != nil,
            hasFailedJob: sessionJobs.contains { $0.status.isFailure },
            hasCompletedJob: sessionJobs.contains {
                $0.status == .completed
            },
            showUploadButton: isAuthenticated,
            onRejectTapped: primaryActivation.map { act in
                { activationToReject = act }
            },
            qrzUploadCount: qrzPendingBySessionId[session.id] ?? 0,
            showQRZUploadButton: hasQRZApiKey,
            onQRZUploadTapped: buildQRZUploadHandler(qsos: qsos),
            onShareTapped: buildShareHandler(
                session: session, activations: activations
            ),
            onExportTapped: primaryActivation == nil ? nil : {
                exportSessionADIF(session: session, activations: activations)
            },
            onMapTapped: primaryActivation == nil ? nil : {
                self.showMap(session: session, activations: activations)
            },
            onEditTapped: primaryActivation.map { act in
                { activationToEdit = act }
            },
            onImportTapped: { sessionToImport = session },
            onSplitExportTapped: { sessionToSplitExport = session },
            onReopenTapped: { sessionToReopen = session },
            onMergeTapped: { sessionToMerge = session }
        )
    }
}
