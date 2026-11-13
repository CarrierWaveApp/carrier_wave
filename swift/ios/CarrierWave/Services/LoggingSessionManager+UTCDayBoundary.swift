import CarrierWaveData
import Foundation
import SwiftData

// MARK: - UTC Day Boundary Monitoring

/// Monitors UTC midnight and auto-splits active POTA sessions when the UTC day rolls over.
/// POTA activations are grouped by UTC date, so a session crossing midnight needs to be
/// split into two sessions — one per UTC day — with the QSO counter resetting for the new day.
extension LoggingSessionManager {
    /// Start a timer that fires at the next UTC midnight.
    /// Only relevant for POTA activations.
    func startUTCMidnightTimer() {
        stopUTCMidnightTimer()

        guard let session = activeSession, session.isPOTA else {
            return
        }

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!

        let now = Date()
        guard let nextMidnight = utcCal.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else {
            return
        }

        let delay = nextMidnight.timeIntervalSince(now)
        utcMidnightTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleUTCDayRollover()
            }
        }
    }

    /// Stop the UTC midnight timer.
    func stopUTCMidnightTimer() {
        utcMidnightTimer?.invalidate()
        utcMidnightTimer = nil
    }

    /// Called at UTC midnight to split the active POTA session.
    func handleUTCDayRollover() {
        guard let session = activeSession, session.isPOTA else {
            startUTCMidnightTimer()
            return
        }

        let completedCount = session.qsoCount

        // End the old session
        completeSessionForDayRollover(session)

        // Start a continuation session for the new UTC day
        let newSession = createContinuationSession(from: session)
        newSession.cloudDirtyFlag = true
        modelContext.insert(newSession)
        activeSession = newSession
        saveActiveSessionId(newSession.id)

        // Store previous day's count for UI display
        previousDayQSOCount = completedCount

        // Old (completed) + new (continuation) session in one coordinated seam write.
        commitSessionSplit(primarySession: session, changes: SessionSplitChanges(sessions: [newSession]))

        // Restart services for the new session
        restartServicesForNewSession()

        ToastManager.shared.show(
            .warning,
            message: "UTC day rolled over. Previous activation: \(completedCount) QSOs. New day started.",
            duration: 8.0
        )

        startUTCMidnightTimer()
    }
}

// MARK: - Day Rollover Helpers

private extension LoggingSessionManager {
    /// End the current session cleanly for a UTC day rollover.
    func completeSessionForDayRollover(_ session: LoggingSession) {
        endLiveActivity()

        if session.isRove {
            var stops = session.roveStops
            if let lastIndex = stops.indices.last, stops[lastIndex].endedAt == nil {
                stops[lastIndex].endedAt = Date()
            }
            session.roveStops = stops
        }

        session.end()
        session.cloudDirtyFlag = true
        session.spotComments = spotCommentsService.comments
    }

    /// Create a new session carrying over all settings from the completed one.
    func createContinuationSession(from old: LoggingSession) -> LoggingSession {
        let newSession = LoggingSession(
            myCallsign: old.myCallsign,
            startedAt: Date(),
            frequency: old.frequency,
            mode: old.mode,
            programs: old.programs,
            activationType: old.activationType,
            parkReference: old.parkReference,
            sotaReference: old.sotaReference,
            missionReference: old.missionReference,
            wwffReference: old.wwffReference,
            myGrid: old.myGrid,
            power: old.power,
            myRig: old.myRig,
            myAntenna: old.myAntenna,
            myKey: old.myKey,
            myMic: old.myMic,
            extraEquipment: old.extraEquipment,
            attendees: old.attendees,
            contestId: old.contestId,
            contestCategory: old.contestCategory,
            contestPower: old.contestPower,
            contestBands: old.contestBands,
            contestOperator: old.contestOperator,
            stationCallsign: old.stationCallsign
        )

        if old.isRove, let park = newSession.parkReference {
            newSession.isRove = true
            let firstStop = RoveStop(
                parkReference: park,
                startedAt: newSession.startedAt,
                myGrid: newSession.myGrid
            )
            newSession.roveStops = [firstStop]
        }

        return newSession
    }

    /// Restart all session services after creating a continuation session.
    func restartServicesForNewSession() {
        startLiveActivity()
        startAutoSpotTimer()
        startSpotCommentsPolling()
        startSpotMonitoring()
        startGridObservation()
    }
}
