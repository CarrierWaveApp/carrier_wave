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

        // Record so the continuity layer doesn't resurrect this session via
        // a CloudKit echo / LAN snapshot that lands shortly after.
        SessionContinuityState.shared.markEnded(session.id)

        endLiveActivity()
        locationService.stop()
        flushTrackPoints(to: session)

        if session.isRove {
            closeOpenRoveStop(on: session)
        }

        // Resolve the own frequency now — clearActiveSessionId() below drops the
        // record before the task runs, and QRT must not go out on a hunted
        // station's frequency (CAR-296).
        let sessionForSpot = session
        let qrtFrequency = spotFrequency(for: session)
        Task { await postQRTSpotIfNeeded(for: sessionForSpot, frequency: qrtFrequency) }

        activeSession = nil
        clearActiveSessionId()
        stopRepeatSpot()
        stopUTCMidnightTimer()
        previousDayQSOCount = nil

        let comments = spotCommentsService.comments
        session.spotComments = comments
        session.cloudDirtyFlag = true

        spotCommentsService.stopPolling()
        spotCommentsService.clear()
        attachedSpotCommentIds = []
        spotMonitoringService.stopMonitoring()

        if webSDRSession.state.isActive {
            Task { await webSDRSession.finalize() }
        }

        disconnectRadio()
        UIApplication.shared.isIdleTimerDisabled = false

        // `.on`: Rust runs end → POTA split → WPM metadata and the results are
        // reflected back. Fallback keeps the Swift ordered monolith intact.
        if !endSessionCoreViaRust(session, comments: comments) {
            session.end()
            var splitChanges: SessionSplitChanges = session.isPOTA
                ? splitPOTAAtUTCMidnight(session)
                : SessionSplitChanges()
            // The WPM metadata is dirtied in this same context, so it must ride the
            // coordinated seam write below — a suppressed save would otherwise drop
            // it from cw-store in `.on` mode.
            if let wpmMetadata = saveAverageWPM(from: comments, session: session) {
                splitChanges.metadata.append(wpmMetadata)
            }
            commitSessionSplit(primarySession: session, changes: splitChanges)
        }
        reportEquipmentUsage(session)

        autoShareCompletedSession(session)
        WidgetDataWriter.clearSession()
        PhoneSessionDelegate.shared.sendSessionEnd()
    }

    private func closeOpenRoveStop(on session: LoggingSession) {
        var stops = session.roveStops
        if let lastIndex = stops.indices.last, stops[lastIndex].endedAt == nil {
            stops[lastIndex].endedAt = Date()
        }
        session.roveStops = stops
    }

    private func autoShareCompletedSession(_ session: LoggingSession) {
        let autoShare = UserDefaults.standard.object(forKey: "shareSessionOnEnd") == nil
            || UserDefaults.standard.bool(forKey: "shareSessionOnEnd")
        guard autoShare else {
            return
        }
        Task { [weak self] in
            await self?.reportSessionCompleted(session)
        }
    }

    /// Pause the current session and return to the session listing
    func pauseSession() {
        guard let session = activeSession else {
            return
        }
        pauseLiveActivity()
        locationService.stop()
        flushTrackPoints(to: session)
        session.cloudDirtyFlag = true

        // Save spot comments to session before clearing
        let comments = spotCommentsService.comments
        session.spotComments = comments

        // `.on`: the pre-mutations above ride the delegation's seam pre-flush and
        // Rust flips the status; the fallback applies the Swift mutation and the
        // trailing commit persists it.
        let delegated = pauseSessionViaRust(session)
        if !delegated {
            session.pause()
        }

        // Clear active session so UI navigates back to listing
        activeSession = nil
        clearActiveSessionId()

        // Stop auto-spot timer while paused
        stopRepeatSpot()

        // Stop UTC midnight timer while paused
        stopUTCMidnightTimer()

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

        // Disconnect radio
        disconnectRadio()

        // Re-enable screen timeout
        UIApplication.shared.isIdleTimerDisabled = false

        if !delegated {
            try? EntityWriteSink.commitUpsert(session, in: modelContext)
        }
    }

    /// Resume a paused session
    func resumeSession() {
        guard let session = activeSession else {
            return
        }
        let delegated = resumeSessionViaRust(session)
        if !delegated {
            session.resume()
        }
        locationService.start()
        startGridObservation()
        resumeLiveActivity()

        // Re-enable screen timeout prevention
        if keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Restart auto-spot timer
        startAutoSpotTimer()

        // Restart UTC midnight timer
        startUTCMidnightTimer()

        // Restart spot comments polling
        startSpotCommentsPolling()

        // Restart spot monitoring
        startSpotMonitoring()

        // Resume WebSDR recording
        if webSDRSession.state == .paused {
            Task { await webSDRSession.resume() }
        }

        // Reconnect radio
        connectRadio()

        if !delegated {
            try? EntityWriteSink.commitUpsert(session, in: modelContext)
        }
    }

    /// Resume a specific session by ID
    func resumeSession(_ session: LoggingSession) {
        // Pause any existing active session (keeps it available to resume later)
        if let existing = activeSession, existing.id != session.id {
            pauseSession()
        }

        // `.on`: the delegation's pre-flush also carries a reopen's `endedAt = nil`
        // mutation into cw-store before Rust flips the status.
        let delegated = resumeSessionViaRust(session)
        if !delegated {
            session.resume()
        }
        activeSession = session
        saveActiveSessionId(session.id)
        locationService.start()
        startGridObservation()
        startLiveActivity()

        // Prevent screen timeout during active session
        if keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Restart auto-spot timer
        startAutoSpotTimer()

        // Restart UTC midnight timer
        startUTCMidnightTimer()

        // Restart spot comments polling
        startSpotCommentsPolling()

        // Restart spot monitoring
        startSpotMonitoring()

        // Reconnect radio
        connectRadio()

        if !delegated {
            try? EntityWriteSink.commitUpsert(session, in: modelContext)
        }
    }

    /// Delete the current session and all its QSOs
    /// This removes the session and hides all associated QSOs so they won't sync
    func deleteCurrentSession() {
        guard let session = activeSession else {
            return
        }

        endLiveActivity()
        locationService.stop()

        // End the session first to properly mark it as completed
        session.end()

        // Hide all QSOs and remove session spots (collected for the seam write)
        let sessionId = session.id
        let hiddenQSOs = hideQSOs(inSession: sessionId)
        let deletedSpots = deleteSessionSpots(inSession: sessionId)

        // Clean up session photos
        try? SessionPhotoManager.deleteAllPhotos(for: session.id)

        // Delete the session itself
        modelContext.delete(session)
        activeSession = nil
        clearActiveSessionId()

        // Stop timers and services
        stopRepeatSpot()
        spotCommentsService.stopPolling()
        spotCommentsService.clear()
        attachedSpotCommentIds = []
        spotMonitoringService.stopMonitoring()

        // Finalize WebSDR recording
        if webSDRSession.state.isActive {
            Task { await webSDRSession.finalize() }
        }

        // Disconnect radio
        disconnectRadio()

        // Re-enable screen timeout
        UIApplication.shared.isIdleTimerDisabled = false

        commitSessionDeleteViaRustOrSeam(session: session, spots: deletedSpots, hiddenQSOs: hiddenQSOs)
    }

    /// Pause a specific non-active session (e.g., from the active sessions list)
    func pauseOtherSession(_ session: LoggingSession) {
        guard session.id != activeSession?.id else {
            // Use normal pauseSession flow for the current active session
            pauseSession()
            return
        }

        if !pauseSessionViaRust(session) {
            session.pause()
            try? EntityWriteSink.commitUpsert(session, in: modelContext)
        }
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
        if !finishPausedSessionViaRust(session) {
            session.end()
            try? EntityWriteSink.commitUpsert(session, in: modelContext)
        }
    }

    /// Reopen a completed session so the user can log more QSOs.
    /// Clears endedAt and transitions to active via the existing resume flow.
    func reopenSession(_ session: LoggingSession) {
        session.endedAt = nil
        session.cloudDirtyFlag = true
        resumeSession(session)
    }

    /// Merge QSOs from source session into target session, then delete source.
    func mergeSessions(source: LoggingSession, into target: LoggingSession) {
        let sourceId = source.id
        let targetId = target.id

        // Any live SessionDetailView for the target loaded its QSOs once in
        // `.task`; without this signal its QSO map/stats never regenerate.
        defer {
            NotificationCenter.default.post(
                name: .sessionQSOsDidChange,
                object: targetId
            )
        }

        // `.on`: Rust performs the whole merge in cw-store first (reassign +
        // bounds + counts + photos + source delete); the identical SwiftData
        // mutations below are then flushed suppressed. Fallback routes one
        // coordinated seam write.
        let delegated = mergeSessionsViaRust(sourceId: sourceId, targetId: targetId)

        let movedQSOs = reassignQSOs(from: sourceId, to: targetId)

        // Expand target time bounds to cover source
        if source.startedAt < target.startedAt {
            target.startedAt = source.startedAt
        }
        if let srcEnd = source.endedAt, let tgtEnd = target.endedAt {
            if srcEnd > tgtEnd {
                target.endedAt = srcEnd
            }
        }

        // Recalculate target QSO count
        target.qsoCount += source.qsoCount

        target.cloudDirtyFlag = true

        // Move photo references to target (files stay on disk —
        // SessionPhotoManager uses filename, not sessionId).
        for filename in source.photoFilenames {
            target.photoFilenames.append(filename)
        }

        let (movedSpots, movedRecordings) = reassignSessionData(from: sourceId, to: targetId)
        modelContext.delete(source)

        if delegated {
            // Rust already wrote every cw-store row — flush SwiftData suppressed.
            try? flushSuppressed()
            return
        }
        // Coordinated seam write: every co-mutated entity reaches cw-store under
        // one suppression window in `on` mode; plain save otherwise.
        guard var seam = SeamWriteBatch.make() else {
            try? modelContext.save()
            return
        }
        seam.upsert(target)
        for qso in movedQSOs {
            seam.upsertQSO(qso)
        }
        for spot in movedSpots {
            seam.upsert(spot)
        }
        for recording in movedRecordings {
            seam.upsert(recording)
        }
        seam.delete(source)
        try? seam.commit(in: modelContext)
    }

    // MARK: Private

    /// Re-point every QSO of `sourceId` at `targetId` (mutation only — the caller
    /// owns persistence). Merge is rare; the existing code already held every
    /// reassigned QSO dirty for a single save, so memory is unchanged.
    private func reassignQSOs(from sourceId: UUID, to targetId: UUID) -> [QSO] {
        let batchSize = 1_000
        var offset = 0
        var reassignedQSOs: [QSO] = []
        while true {
            let predicate = #Predicate<QSO> {
                $0.loggingSessionId == sourceId
            }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            guard let batch = try? modelContext.fetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }
            for qso in batch {
                qso.loggingSessionId = targetId
                reassignedQSOs.append(qso)
            }
            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }
        return reassignedQSOs
    }

    /// Re-point spots and recordings from source to target session (mutation
    /// only — the caller owns persistence). Returns what moved.
    private func reassignSessionData(
        from sourceId: UUID, to targetId: UUID
    ) -> (spots: [SessionSpot], recordings: [WebSDRRecording]) {
        // Move session spots
        let spotPredicate = #Predicate<SessionSpot> {
            $0.loggingSessionId == sourceId
        }
        var movedSpots: [SessionSpot] = []
        if let spots = try? modelContext.fetch(
            FetchDescriptor(predicate: spotPredicate)
        ) {
            for spot in spots {
                spot.loggingSessionId = targetId
            }
            movedSpots = spots
        }

        // Move SDR recordings
        let recPredicate = #Predicate<WebSDRRecording> {
            $0.loggingSessionId == sourceId
        }
        var movedRecordings: [WebSDRRecording] = []
        if let recordings = try? modelContext.fetch(
            FetchDescriptor(predicate: recPredicate)
        ) {
            for recording in recordings {
                recording.loggingSessionId = targetId
            }
            movedRecordings = recordings
        }
        return (movedSpots, movedRecordings)
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

        // Hide all QSOs and remove session spots (collected for the seam write)
        let hiddenQSOs = hideQSOs(inSession: sessionId)
        let deletedSpots = deleteSessionSpots(inSession: sessionId)

        // Clean up session photos
        try? SessionPhotoManager.deleteAllPhotos(for: sessionId)

        // Delete the session
        modelContext.delete(session)
        commitSessionDeleteViaRustOrSeam(session: session, spots: deletedSpots, hiddenQSOs: hiddenQSOs)
    }
}
