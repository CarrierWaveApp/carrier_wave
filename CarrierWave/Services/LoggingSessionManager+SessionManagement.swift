import CarrierWaveData
import Foundation
import SwiftData
import UIKit

// MARK: - Session Lifecycle and Management

extension LoggingSessionManager {
    /// End the current session
    func endSession() {
        guard let session = activeSession else {
            return
        }

        endLiveActivity()

        // Close the current rove stop if active
        if session.isRove {
            var stops = session.roveStops
            if let lastIndex = stops.indices.last, stops[lastIndex].endedAt == nil {
                stops[lastIndex].endedAt = Date()
            }
            session.roveStops = stops
        }

        // Post QRT spot before cleanup (fire and forget)
        // Capture session before it's cleared
        let sessionForSpot = session
        Task {
            await postQRTSpotIfNeeded(for: sessionForSpot)
        }

        session.end()

        // Split POTA sessions at UTC midnight so each covers one activation date
        if session.isPOTA {
            splitPOTAAtUTCMidnight(session)
        }

        activeSession = nil
        clearActiveSessionId()

        // Stop auto-spot timer
        stopAutoSpotTimer()

        // Save spot comments to session before clearing
        let comments = spotCommentsService.comments
        session.spotComments = comments

        // Persist average WPM to activation metadata if this is a POTA session with RBN data
        saveAverageWPM(from: comments, session: session)

        // Stop spot comments polling
        spotCommentsService.stopPolling()
        spotCommentsService.clear()
        attachedSpotCommentIds = []

        // Stop spot monitoring
        spotMonitoringService.stopMonitoring()

        // Finalize WebSDR recording if active
        if webSDRSession.state.isActive {
            Task { await webSDRSession.finalize() }
        }

        // Disconnect BLE radio
        disconnectBLERadio()

        // Re-enable screen timeout
        UIApplication.shared.isIdleTimerDisabled = false

        try? modelContext.save()

        // Report session completed activity (fire and forget)
        let autoShare = UserDefaults.standard.object(forKey: "shareSessionOnEnd") == nil
            || UserDefaults.standard.bool(forKey: "shareSessionOnEnd")
        if autoShare {
            let completedSession = session
            Task { [weak self] in
                await self?.reportSessionCompleted(completedSession)
            }
        }

        WidgetDataWriter.clearSession()
        PhoneSessionDelegate.shared.sendSessionEnd()
    }

    /// Pause the current session and return to the session listing
    func pauseSession() {
        guard let session = activeSession else {
            return
        }
        pauseLiveActivity()
        session.pause()

        // Save spot comments to session before clearing
        let comments = spotCommentsService.comments
        session.spotComments = comments

        // Clear active session so UI navigates back to listing
        activeSession = nil
        clearActiveSessionId()

        // Stop auto-spot timer while paused
        stopAutoSpotTimer()

        // Pause spot comments polling
        spotCommentsService.stopPolling()
        spotCommentsService.clear()
        attachedSpotCommentIds = []

        // Pause spot monitoring
        spotMonitoringService.stopMonitoring()

        // Pause WebSDR recording
        if webSDRSession.state == .recording {
            Task { await webSDRSession.pause() }
        }

        // Disconnect BLE radio
        disconnectBLERadio()

        // Re-enable screen timeout
        UIApplication.shared.isIdleTimerDisabled = false

        try? modelContext.save()
    }

    /// Resume a paused session
    func resumeSession() {
        guard let session = activeSession else {
            return
        }
        session.resume()
        resumeLiveActivity()

        // Re-enable screen timeout prevention
        if keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Restart auto-spot timer
        startAutoSpotTimer()

        // Restart spot comments polling
        startSpotCommentsPolling()

        // Restart spot monitoring
        startSpotMonitoring()

        // Resume WebSDR recording
        if webSDRSession.state == .paused {
            Task { await webSDRSession.resume() }
        }

        // Reconnect BLE radio
        connectBLERadio()

        try? modelContext.save()
    }

    /// Resume a specific session by ID
    func resumeSession(_ session: LoggingSession) {
        // Pause any existing active session (keeps it available to resume later)
        if let existing = activeSession, existing.id != session.id {
            pauseSession()
        }

        session.resume()
        activeSession = session
        saveActiveSessionId(session.id)
        startLiveActivity()

        // Prevent screen timeout during active session
        if keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Restart auto-spot timer
        startAutoSpotTimer()

        // Restart spot comments polling
        startSpotCommentsPolling()

        // Restart spot monitoring
        startSpotMonitoring()

        // Reconnect BLE radio
        connectBLERadio()

        try? modelContext.save()
    }

    /// Delete the current session and all its QSOs
    /// This removes the session and hides all associated QSOs so they won't sync
    func deleteCurrentSession() {
        guard let session = activeSession else {
            return
        }

        endLiveActivity()

        // End the session first to properly mark it as completed
        session.end()

        // Hide all QSOs in this session
        let sessionId = session.id
        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == sessionId
        }

        let descriptor = FetchDescriptor<QSO>(predicate: predicate)

        do {
            let qsos = try modelContext.fetch(descriptor)
            for qso in qsos {
                qso.isHidden = true
                // Clear upload flags so hidden QSOs are never synced
                for presence in qso.servicePresence where presence.needsUpload {
                    presence.needsUpload = false
                }
            }
        } catch {
            // Continue with session deletion even if QSO hiding fails
        }

        // Clean up session spots
        let spotPredicate = #Predicate<SessionSpot> { spot in
            spot.loggingSessionId == sessionId
        }
        let spotDescriptor = FetchDescriptor<SessionSpot>(predicate: spotPredicate)
        if let spots = try? modelContext.fetch(spotDescriptor) {
            for spot in spots {
                modelContext.delete(spot)
            }
        }

        // Clean up session photos
        try? SessionPhotoManager.deleteAllPhotos(for: session.id)

        // Delete the session itself
        modelContext.delete(session)
        activeSession = nil
        clearActiveSessionId()

        // Stop timers and services
        stopAutoSpotTimer()
        spotCommentsService.stopPolling()
        spotCommentsService.clear()
        attachedSpotCommentIds = []
        spotMonitoringService.stopMonitoring()

        // Finalize WebSDR recording
        if webSDRSession.state.isActive {
            Task { await webSDRSession.finalize() }
        }

        // Disconnect BLE radio
        disconnectBLERadio()

        // Re-enable screen timeout
        UIApplication.shared.isIdleTimerDisabled = false

        try? modelContext.save()
    }

    /// Get recent sessions for resuming
    func getRecentSessions(limit: Int = 10) -> [LoggingSession] {
        let descriptor = FetchDescriptor<LoggingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        do {
            var fetchDescriptor = descriptor
            fetchDescriptor.fetchLimit = limit
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            return []
        }
    }

    /// Get all active or paused sessions (not completed), excluding the current active session
    func fetchActiveSessions() -> [LoggingSession] {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate {
                $0.statusRawValue == "active" || $0.statusRawValue == "paused"
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50

        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        let activeId = activeSession?.id
        return sessions.filter { $0.id != activeId }
    }

    /// Pause a specific non-active session (e.g., from the active sessions list)
    func pauseOtherSession(_ session: LoggingSession) {
        guard session.id != activeSession?.id else {
            // Use normal pauseSession flow for the current active session
            pauseSession()
            return
        }

        session.pause()
        try? modelContext.save()
    }

    /// Finish (complete) a specific session that is active or paused
    func finishSession(_ session: LoggingSession) {
        if session.id == activeSession?.id {
            // Finishing the current active session - use normal endSession flow
            endSession()
            return
        }

        // Finish a non-active (paused) session
        // End any live activity that may still be showing from the paused state
        liveActivityService.end()
        session.end()
        try? modelContext.save()
    }

    /// Delete a specific session, hiding its QSOs and cleaning up associated data
    func deleteSession(_ session: LoggingSession) {
        if session.id == activeSession?.id {
            endSession()
        } else {
            // End any live activity that may still be showing from the paused state
            liveActivityService.end()
        }

        let sessionId = session.id

        // Hide all QSOs in this session
        let predicate = #Predicate<QSO> { $0.loggingSessionId == sessionId }
        if let qsos = try? modelContext.fetch(FetchDescriptor(predicate: predicate)) {
            for qso in qsos {
                qso.isHidden = true
                for presence in qso.servicePresence where presence.needsUpload {
                    presence.needsUpload = false
                }
            }
        }

        // Clean up session spots
        let spotPredicate = #Predicate<SessionSpot> { $0.loggingSessionId == sessionId }
        if let spots = try? modelContext.fetch(FetchDescriptor(predicate: spotPredicate)) {
            for spot in spots {
                modelContext.delete(spot)
            }
        }

        // Clean up session photos
        try? SessionPhotoManager.deleteAllPhotos(for: sessionId)

        // Delete the session
        modelContext.delete(session)
        try? modelContext.save()
    }
}
