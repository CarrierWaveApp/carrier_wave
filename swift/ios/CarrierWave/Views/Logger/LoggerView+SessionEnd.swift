import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - LoggerView Session End

extension LoggerView {
    // MARK: - Session End Handling

    /// Handle end session action — shows multi-step end session flow
    func handleEndSession() {
        guard let session = sessionManager?.activeSession else {
            completeSessionEnd()
            return
        }

        // Populate POTA upload state if applicable
        if session.isPOTA, !potaUploadPromptDisabled {
            let qsosNeedingUpload = sessionQSOs.filter { $0.needsUpload(to: .pota) }
            if !qsosNeedingUpload.isEmpty {
                pendingSessionEndQSOs = qsosNeedingUpload
                if session.isRove {
                    populateRoveUploadState(session: session, qsos: qsosNeedingUpload)
                } else if let parkRef = session.parkReference {
                    pendingSessionEndRoveStops = []
                    pendingSessionEndParkRef = parkRef
                    pendingSessionEndParkName = lookupParkName(parkRef)
                    pendingSessionEndQSOCount = qsosNeedingUpload.count
                }

                pendingSessionEndInMaintenance = POTAClient.isInMaintenanceWindow()
                pendingSessionEndMaintenanceRemaining =
                    pendingSessionEndInMaintenance
                        ? POTAClient.formatMaintenanceTimeRemaining() : nil
            }
        }

        showEndSessionFlow = true
    }

    private func populateRoveUploadState(session: LoggingSession, qsos: [QSO]) {
        let stops = session.mergedRoveStops
        var summaries: [RoveUploadSummary] = []
        for stop in stops {
            let parkRef = stop.parkReference
            let stopQSOs = qsos.filter {
                $0.parkReference?.uppercased() == parkRef.uppercased()
            }
            guard !stopQSOs.isEmpty else {
                continue
            }
            let primaryPark = ParkReference.split(parkRef).first ?? parkRef
            summaries.append(RoveUploadSummary(
                parkReference: primaryPark,
                parkName: lookupParkName(primaryPark),
                qsoCount: stopQSOs.count
            ))
        }
        pendingSessionEndRoveStops = summaries
        pendingSessionEndParkRef = session.parkReference
        pendingSessionEndParkName = nil
        pendingSessionEndQSOCount = qsos.count
    }

    /// Actually end the session and build the activity item for the brag sheet
    func performSessionEnd() {
        guard sessionManager?.activeSession != nil else {
            return
        }

        let hadQSOs = !sessionQSOs.isEmpty
        teardownContestManager()
        sessionManager?.endSession()
        if hadQSOs {
            onSessionEnd?()
        }

        // Find the just-created ActivityItem for the brag sheet display
        endSessionActivityItem = fetchLatestOwnActivity()
    }

    /// Complete the session end flow (called when the flow sheet is dismissed)
    func completeSessionEnd() {
        let hadQSOs = !sessionQSOs.isEmpty
        if sessionManager?.activeSession != nil {
            teardownContestManager()
            sessionManager?.endSession()
            if hadQSOs {
                onSessionEnd?()
            }
            // Server-sync snapshot cadence check on session end (Phase 7.4).
            Task {
                await ServerSnapshotCoordinator.snapshotIfDue(trigger: "session-end")
            }
        }

        // Clear pending state
        pendingSessionEndParkRef = nil
        pendingSessionEndParkName = nil
        pendingSessionEndQSOCount = 0
        pendingSessionEndQSOs = []
        pendingSessionEndRoveStops = []
        pendingSessionEndInMaintenance = false
        pendingSessionEndMaintenanceRemaining = nil
        endSessionActivityItem = nil
    }

    /// Upload pending POTA QSOs from the upload prompt (supports multi-park)
    func uploadPendingPOTAQSOs() async -> Bool {
        guard let parkRef = pendingSessionEndParkRef,
              !pendingSessionEndQSOs.isEmpty
        else {
            return false
        }

        let parks = ParkReference.split(parkRef)
        let potaClient = POTAClient(authService: POTAAuthService())
        var allSucceeded = true

        for park in parks {
            do {
                let result = try await potaClient.uploadActivationWithRecording(
                    parkReference: park,
                    qsos: pendingSessionEndQSOs,
                    modelContext: modelContext
                )

                if result.success {
                    for qso in pendingSessionEndQSOs {
                        qso.markSubmittedToPark(park, context: modelContext)
                    }
                    try? modelContext.save()
                } else {
                    allSucceeded = false
                    SyncDebugLog.shared.warning(
                        "POTA upload for \(park): result.success=false, "
                            + "message=\(result.message ?? "nil")",
                        service: .pota
                    )
                }
            } catch {
                allSucceeded = false
                SyncDebugLog.shared.error(
                    "POTA upload for \(park) failed: \(error.localizedDescription)",
                    service: .pota
                )
            }
        }

        return allSucceeded
    }
}
