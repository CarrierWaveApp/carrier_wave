import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - Frequency, Mode, and Notes

extension LoggingSessionManager {
    /// Update operating frequency
    /// Returns info about whether to prompt for spot and suggested mode
    /// Set `isTuningToSpot` when temporarily changing frequency to work a spotted station
    func updateFrequency(
        _ frequency: Double,
        isTuningToSpot: Bool = false
    ) -> FrequencyUpdateResult {
        guard let session = activeSession else {
            return FrequencyUpdateResult(
                shouldPromptForSpot: false, suggestedMode: nil, isFirstFrequencySet: false
            )
        }

        let oldFrequency = session.frequency
        let isFirstSet = oldFrequency == nil
        session.updateFrequency(frequency)
        try? modelContext.save()
        updateLiveActivity()

        // Retune WebSDR if recording
        if webSDRSession.state == .recording {
            Task { await webSDRSession.retune(frequencyMHz: frequency) }
        }

        // If this is the first frequency set on a POTA session, trigger an initial spot
        // Skip if tuning to a spot -- don't self-spot on the hunted station's frequency
        // Only auto-spot if the user has auto-spotting enabled
        if isFirstSet, potaAutoSpotEnabled,
           session.isPOTA, !isTuningToSpot
        {
            Task {
                await postSpot()
            }
        }

        // Check if mode should change based on frequency
        let suggestedMode = BandPlanService.suggestedMode(for: frequency)
        let currentMode = session.mode.uppercased()

        // Only suggest if different from current mode
        let modeToSuggest: String? =
            if let suggested = suggestedMode, suggested != currentMode {
                suggested
            } else {
                nil
            }

        // Check if this QSY should prompt for a POTA spot
        let shouldPromptForSpot =
            potaQSYSpotEnabled && session.isPOTA
                && !isFirstSet && !isTuningToSpot && oldFrequency != frequency
                && isValidForQSYSpot(frequency: frequency, mode: modeToSuggest ?? currentMode)

        return FrequencyUpdateResult(
            shouldPromptForSpot: shouldPromptForSpot,
            suggestedMode: modeToSuggest,
            isFirstFrequencySet: isFirstSet
        )
    }

    /// Post a QSY spot (called from LoggerView after user confirmation)
    func postQSYSpot() async {
        await postSpot(comment: "QSY", showToast: true)
    }

    /// Update operating mode
    /// Returns true if a QSY spot prompt should be shown (POTA session with mode change)
    @discardableResult
    func updateMode(_ mode: String) -> Bool {
        guard let session = activeSession else {
            return false
        }

        let oldMode = session.mode
        session.updateMode(mode)
        try? modelContext.save()
        updateLiveActivity()

        // Retune WebSDR if recording
        if webSDRSession.state == .recording {
            Task { await webSDRSession.changeMode(mode, frequencyMHz: session.frequency) }
        }

        // Return whether this is a QSY that could be spotted
        // Only prompt if QSY spots are enabled in settings
        return potaQSYSpotEnabled
            && session.isPOTA
            && oldMode != mode
    }

    /// Update session title
    func updateTitle(_ title: String?) {
        activeSession?.customTitle = title
        try? modelContext.save()
    }

    /// Update park reference for the current session
    /// Only valid for POTA activations
    func updateParkReference(_ parkReference: String?) {
        guard let session = activeSession,
              session.isPOTA
        else {
            return
        }

        session.parkReference = parkReference.flatMap { ParkReference.sanitizeMulti($0) }
        try? modelContext.save()
        updateLiveActivity()

        // Restart spot comments polling with new park reference
        spotCommentsService.stopPolling()
        spotCommentsService.clear()
        startSpotCommentsPolling()
    }

    /// Append a note to the session log
    /// Notes are stored with ISO8601 timestamps for sorting: [ISO8601|HH:mm] text
    func appendNote(_ text: String) {
        guard let session = activeSession else {
            return
        }

        let timestamp = Date()

        // ISO8601 for sorting, HH:mm for display
        let isoFormatter = ISO8601DateFormatter()
        let isoString = isoFormatter.string(from: timestamp)

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "HH:mm"
        displayFormatter.timeZone = TimeZone(identifier: "UTC")
        let displayTime = displayFormatter.string(from: timestamp)

        // Format: [ISO8601|HH:mm] text
        let noteEntry = "[\(isoString)|\(displayTime)] \(text)"

        if let existingNotes = session.notes, !existingNotes.isEmpty {
            session.notes = existingNotes + "\n" + noteEntry
        } else {
            session.notes = noteEntry
        }

        try? modelContext.save()
    }

    /// Parse session notes into individual entries with timestamps
    func parseSessionNotes() -> [SessionNoteEntry] {
        guard let session = activeSession, let notes = session.notes, !notes.isEmpty else {
            return []
        }

        var entries: [SessionNoteEntry] = []
        let lines = notes.components(separatedBy: "\n")

        for line in lines {
            if let entry = SessionNoteEntry.parse(line) {
                entries.append(entry)
            }
        }

        return entries
    }
}
