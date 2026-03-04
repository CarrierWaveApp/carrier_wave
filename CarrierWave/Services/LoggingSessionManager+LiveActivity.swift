import CarrierWaveData
import Foundation

// MARK: - Live Activity Integration

extension LoggingSessionManager {
    /// Start a Live Activity for the current session
    func startLiveActivity() {
        guard let session = activeSession else {
            return
        }

        let attributes = LoggingSessionAttributes(
            myCallsign: session.myCallsign,
            activationType: session.activationType.displayName,
            startedAt: session.startedAt
        )

        let state = buildContentState(for: session)
        liveActivityService.start(attributes: attributes, state: state)
    }

    /// Update the Live Activity with current session state
    func updateLiveActivity(lastCallsign: String? = nil) {
        guard let session = activeSession else {
            return
        }

        var state = buildContentState(for: session)
        if let callsign = lastCallsign {
            state.lastCallsign = callsign
        }
        liveActivityService.update(state: state)
    }

    /// End the Live Activity
    func endLiveActivity() {
        liveActivityService.end()
    }

    /// Update Live Activity to show paused state
    func pauseLiveActivity() {
        guard let session = activeSession else {
            return
        }

        var state = buildContentState(for: session)
        state.isPaused = true
        liveActivityService.update(state: state)
    }

    /// Update Live Activity to show resumed state
    func resumeLiveActivity() {
        guard let session = activeSession else {
            return
        }

        let state = buildContentState(for: session)
        liveActivityService.update(state: state)
    }

    // MARK: - Private

    private func buildContentState(
        for session: LoggingSession
    ) -> LoggingSessionAttributes.ContentState {
        let freqString = session.frequency.map { String(format: "%.3f", $0) }
        let bandString = session.band

        // Rove stop info
        var currentStopPark: String?
        var stopNumber: Int?
        var totalStops: Int?
        var currentStopQSOs: Int?

        if session.isRove {
            let stops = session.roveStops
            totalStops = stops.count
            if let current = session.currentRoveStop,
               let index = stops.firstIndex(where: { $0.id == current.id })
            {
                currentStopPark = current.parkReference
                stopNumber = index + 1
                currentStopQSOs = current.qsoCount
            }
        }

        return LoggingSessionAttributes.ContentState(
            qsoCount: session.qsoCount,
            frequency: freqString,
            band: bandString,
            mode: session.mode,
            parkReference: session.parkReference,
            lastCallsign: nil,
            isPaused: session.status == .paused,
            updatedAt: Date(),
            currentStopPark: currentStopPark,
            stopNumber: stopNumber,
            totalStops: totalStops,
            currentStopQSOs: currentStopQSOs
        )
    }
}
