// swiftlint:disable identifier_name file_length
import CarrierWaveCore
import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - LoggingSessionManager

/// Manages logging session lifecycle and QSO creation
@MainActor
@Observable
// swiftlint:disable:next type_body_length
final class LoggingSessionManager {
    // MARK: Lifecycle

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadActiveSession()
    }

    // MARK: Internal

    /// Result of a frequency update
    struct FrequencyUpdateResult {
        /// Whether a QSY spot prompt should be shown
        let shouldPromptForSpot: Bool
        /// Suggested mode for the new frequency (nil if no change needed)
        let suggestedMode: String?
        /// Whether this was the first frequency set on a hunt-first session
        let isFirstFrequencySet: Bool
    }

    /// Currently active session
    private(set) var activeSession: LoggingSession?

    /// Service for polling POTA spot comments
    let spotCommentsService = SpotCommentsService()

    /// Service for monitoring RBN/POTA spots during session
    let spotMonitoringService = SpotMonitoringService()

    /// WebSDR recording session (optional, user-initiated)
    let webSDRSession = WebSDRSession()

    let modelContext: ModelContext

    /// Timer for auto-spotting to POTA (accessed by +Spotting extension)
    var autoSpotTimer: Timer?

    /// Auto-spot interval (10 minutes) (accessed by +Spotting extension)
    let autoSpotInterval: TimeInterval = 10 * 60

    /// Track which spot comment IDs have been attached to QSOs (accessed by +Spotting extension)
    var attachedSpotCommentIds: Set<Int64> = []

    /// Whether there's an active session
    var hasActiveSession: Bool {
        activeSession != nil
    }

    /// Start a new logging session
    func startSession(
        myCallsign: String,
        mode: String,
        frequency: Double? = nil,
        activationType: ActivationType = .casual,
        parkReference: String? = nil,
        sotaReference: String? = nil,
        myGrid: String? = nil,
        power: Int? = nil,
        myRig: String? = nil,
        myAntenna: String? = nil,
        myKey: String? = nil,
        myMic: String? = nil,
        extraEquipment: String? = nil,
        attendees: String? = nil,
        isRove: Bool = false
    ) {
        // Pause any existing session first (keeps it available to resume later)
        if activeSession != nil {
            pauseSession()
        }

        let session = LoggingSession(
            myCallsign: myCallsign,
            startedAt: Date(),
            frequency: frequency,
            mode: mode,
            activationType: activationType,
            parkReference: parkReference.flatMap { ParkReference.sanitizeMulti($0) },
            sotaReference: sotaReference,
            myGrid: myGrid,
            power: power,
            myRig: myRig,
            myAntenna: myAntenna,
            myKey: myKey,
            myMic: myMic,
            extraEquipment: extraEquipment,
            attendees: attendees
        )

        // Set up rove mode with first stop
        if isRove, activationType == .pota, let park = session.parkReference {
            session.isRove = true
            let firstStop = RoveStop(
                parkReference: park,
                startedAt: session.startedAt,
                myGrid: myGrid
            )
            session.roveStops = [firstStop]
        }

        modelContext.insert(session)
        activeSession = session
        saveActiveSessionId(session.id)

        // Cache service configuration to avoid Keychain reads per-QSO
        cacheServiceConfiguration()

        // Prevent screen timeout during active session
        if keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Start auto-spot timer for POTA activations
        startAutoSpotTimer()

        // Start spot comments polling for POTA activations
        startSpotCommentsPolling()

        // Start spot monitoring
        startSpotMonitoring()

        // Auto-record solar/weather conditions for POTA activations
        recordConditions()

        try? modelContext.save()

        writeSessionToWidget(session)
    }

    /// Advance to the next park stop in a rove session
    func nextRoveStop(
        parkReference: String,
        myGrid: String?,
        postQRTSpot: Bool,
        autoSpotNewPark: Bool
    ) {
        guard let session = activeSession, session.isRove else {
            return
        }

        let sanitizedPark = ParkReference.sanitizeMulti(parkReference) ?? parkReference

        // Close the current stop
        var stops = session.roveStops
        if let lastIndex = stops.indices.last, stops[lastIndex].endedAt == nil {
            stops[lastIndex].endedAt = Date()
        }

        // Create new stop — fall back to session grid if no grid provided
        let stopGrid = myGrid ?? session.myGrid
        let newStop = RoveStop(
            parkReference: sanitizedPark,
            startedAt: Date(),
            myGrid: stopGrid
        )
        stops.append(newStop)
        session.roveStops = stops

        // Capture old park for QRT spot before updating
        let oldParkRef = session.parkReference

        // Update session to the new park
        session.parkReference = sanitizedPark
        if let grid = myGrid {
            session.myGrid = grid
        }

        try? modelContext.save()

        // Post QRT spot for the old park (fire and forget)
        if postQRTSpot, let oldPark = oldParkRef {
            Task {
                await postQRTSpotForPark(oldPark, session: session)
            }
        }

        // Restart spot comments polling for the new park
        spotCommentsService.stopPolling()
        spotCommentsService.clear()
        attachedSpotCommentIds = []
        startSpotCommentsPolling()

        // Post initial spot for the new park
        if autoSpotNewPark {
            Task {
                await postSpot()
            }
        }
    }

    /// Increment the current rove stop's QSO count
    func incrementCurrentRoveStopQSOCount() {
        guard let session = activeSession, session.isRove else {
            return
        }
        var stops = session.roveStops
        if let lastIndex = stops.indices.last, stops[lastIndex].endedAt == nil {
            stops[lastIndex].qsoCount += 1
            session.roveStops = stops
        }
    }

    /// End the current session
    func endSession() {
        guard let session = activeSession else {
            return
        }

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

        // Re-enable screen timeout
        UIApplication.shared.isIdleTimerDisabled = false

        try? modelContext.save()

        WidgetDataWriter.clearSession()
    }

    /// Pause the current session and return to the session listing
    func pauseSession() {
        guard let session = activeSession else {
            return
        }
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

        try? modelContext.save()
    }

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

        // Retune WebSDR if recording
        if webSDRSession.state == .recording {
            Task { await webSDRSession.retune(frequencyMHz: frequency) }
        }

        // If this is the first frequency set on a POTA session, trigger an initial spot
        // Skip if tuning to a spot — don't self-spot on the hunted station's frequency
        if isFirstSet, session.activationType == .pota, !isTuningToSpot {
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

        // Check if this is a QSY that could be spotted
        // Don't prompt for spot if:
        // - QSY spots are disabled in settings
        // - Frequency is outside amateur bands or violates license
        // - This is the first frequency set (we already auto-spotted above)
        // - Tuning to a spot (temporary frequency change for hunting)
        var shouldPromptForSpot = false
        if potaQSYSpotEnabled,
           session.activationType == .pota,
           !isFirstSet,
           !isTuningToSpot,
           oldFrequency != frequency
        {
            // Get user's license class
            let licenseRaw =
                UserDefaults.standard.string(forKey: "userLicenseClass")
                    ?? LicenseClass.extra.rawValue
            let license = LicenseClass(rawValue: licenseRaw) ?? .extra

            // Only prompt for spot if frequency is valid for the user's license
            let violation = BandPlanService.validate(
                frequencyMHz: frequency,
                mode: modeToSuggest ?? currentMode,
                license: license
            )

            // Allow spot prompt only if no violation, or if it's just an unusual frequency warning
            shouldPromptForSpot = violation == nil || violation?.type == .unusualFrequency
        }

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

        // Retune WebSDR if recording
        if webSDRSession.state == .recording {
            Task { await webSDRSession.changeMode(mode, frequencyMHz: session.frequency) }
        }

        // Return whether this is a QSY that could be spotted
        // Only prompt if QSY spots are enabled in settings
        return potaQSYSpotEnabled
            && session.activationType == .pota
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
              session.activationType == .pota
        else {
            return
        }

        session.parkReference = parkReference.flatMap { ParkReference.sanitizeMulti($0) }
        try? modelContext.save()

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

    /// Log a new QSO
    func logQSO(
        callsign: String,
        rstSent: String = "599",
        rstReceived: String = "599",
        theirGrid: String? = nil,
        theirParkReference: String? = nil,
        notes: String? = nil,
        name: String? = nil,
        operatorName: String? = nil,
        state: String? = nil,
        country: String? = nil,
        qth: String? = nil,
        theirLicenseClass: String? = nil
    ) -> QSO? {
        guard let session = activeSession else {
            return nil
        }

        // Derive band from frequency
        let band: String =
            if let freq = session.frequency {
                LoggingSession.bandForFrequency(freq)
            } else {
                "Unknown"
            }

        let qso = QSO(
            callsign: callsign.trimmingCharacters(in: .whitespaces).uppercased(),
            band: band,
            mode: session.mode,
            frequency: session.frequency,
            timestamp: Date(),
            rstSent: rstSent,
            rstReceived: rstReceived,
            myCallsign: session.myCallsign,
            myGrid: session.myGrid,
            theirGrid: theirGrid,
            parkReference: session.parkReference,
            theirParkReference: theirParkReference,
            notes: combineNotes(notes: notes, operatorName: operatorName),
            importSource: .logger,
            name: name,
            qth: qth,
            state: state,
            country: country,
            power: session.power,
            myRig: session.myRig,
            theirLicenseClass: theirLicenseClass
        )

        // Set the logging session ID
        qso.loggingSessionId = session.id

        modelContext.insert(qso)
        session.incrementQSOCount()

        // Increment per-stop QSO count for rove sessions
        incrementCurrentRoveStopQSOCount()

        // Mark for upload to configured services
        markForUpload(qso)

        try? modelContext.save()

        writeSessionToWidget(session, lastCallsign: qso.callsign)

        // Detect and report social activities async (non-blocking)
        Task { [weak self] in
            await self?.processActivityForQSO(qso)
        }

        return qso
    }

    /// Hide a QSO (soft delete)
    func hideQSO(_ qso: QSO) {
        qso.isHidden = true
        // Clear upload flags so hidden QSOs are never synced
        for presence in qso.servicePresence where presence.needsUpload {
            presence.needsUpload = false
        }
        try? modelContext.save()
    }

    /// Unhide a previously hidden QSO
    func unhideQSO(_ qso: QSO) {
        qso.isHidden = false
        try? modelContext.save()
    }

    /// Delete the current session and all its QSOs
    /// This removes the session and hides all associated QSOs so they won't sync
    func deleteCurrentSession() {
        guard let session = activeSession else {
            return
        }

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
        session.end()
        try? modelContext.save()
    }

    /// Delete a specific session, hiding its QSOs and cleaning up associated data
    func deleteSession(_ session: LoggingSession) {
        if session.id == activeSession?.id {
            endSession()
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

    /// Get QSOs for the current session
    func getSessionQSOs() -> [QSO] {
        guard let session = activeSession else {
            return []
        }

        let sessionId = session.id
        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == sessionId && !qso.isHidden
        }

        let descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    // MARK: - Photo Management

    /// Add a photo to the current session, returning the filename
    func addPhoto(_ image: UIImage) throws -> String {
        guard let session = activeSession else {
            throw SessionPhotoManager.PhotoError.compressionFailed
        }

        let filename = try SessionPhotoManager.savePhoto(image, sessionID: session.id)
        session.photoFilenames.append(filename)
        try? modelContext.save()
        return filename
    }

    /// Delete a photo from the current session
    func deletePhoto(filename: String) throws {
        guard let session = activeSession else {
            return
        }

        try SessionPhotoManager.deletePhoto(filename: filename, sessionID: session.id)
        session.photoFilenames.removeAll { $0 == filename }
        try? modelContext.save()
    }

    // MARK: Private

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    /// These should never be synced to any service
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Cached service configuration (checked once at session start to avoid Keychain reads per-QSO)
    private var qrzConfigured = false
    private var potaConfigured = false
    private var lofiConfigured = false
    private var clublogConfigured = false

    /// Key for storing active session ID in UserDefaults
    private let activeSessionIdKey = "activeLoggingSessionId"

    /// Whether to keep screen on during active session (from settings)
    /// Defaults to true if the setting hasn't been explicitly set (matches @AppStorage default)
    private var keepScreenOn: Bool {
        if UserDefaults.standard.object(forKey: "loggerKeepScreenOn") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "loggerKeepScreenOn")
    }

    private func writeSessionToWidget(
        _ session: LoggingSession, lastCallsign: String? = nil
    ) {
        let freqString = session.frequency.map { String(format: "%.3f", $0) }
        WidgetDataWriter.writeSession(WidgetSessionSnapshot(
            isActive: true,
            parkReference: session.parkReference,
            parkName: nil,
            frequency: freqString,
            mode: session.mode,
            qsoCount: session.qsoCount,
            startedAt: session.startedAt,
            lastCallsign: lastCallsign,
            activationType: session.activationType.rawValue,
            updatedAt: Date()
        ))
    }

    /// Load active session from persisted ID
    private func loadActiveSession() {
        guard let idString = UserDefaults.standard.string(forKey: activeSessionIdKey),
              let sessionId = UUID(uuidString: idString)
        else {
            return
        }

        let predicate = #Predicate<LoggingSession> { session in
            session.id == sessionId
        }

        let descriptor = FetchDescriptor<LoggingSession>(predicate: predicate)

        do {
            let sessions = try modelContext.fetch(descriptor)
            if let session = sessions.first, session.isActive {
                activeSession = session
                // Cache service configuration for restored session
                cacheServiceConfiguration()
                // Prevent screen timeout for restored active session
                if keepScreenOn {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                // Restart auto-spot timer for restored POTA session
                startAutoSpotTimer()
                // Restart spot comments polling for restored POTA session
                startSpotCommentsPolling()
                // Restart spot monitoring for restored session
                startSpotMonitoring()
            } else {
                // Session was ended or not found, clear the stored ID
                clearActiveSessionId()
            }
        } catch {
            clearActiveSessionId()
        }
    }

    /// Save active session ID to UserDefaults
    private func saveActiveSessionId(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeSessionIdKey)
    }

    /// Clear active session ID from UserDefaults
    private func clearActiveSessionId() {
        UserDefaults.standard.removeObject(forKey: activeSessionIdKey)
    }

    /// Combine notes and operator name into a single notes field
    private func combineNotes(notes: String?, operatorName: String?) -> String? {
        var parts: [String] = []

        if let op = operatorName, !op.isEmpty {
            parts.append("OP: \(op)")
        }

        if let n = notes, !n.isEmpty {
            parts.append(n)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    /// Cache service configuration to avoid Keychain reads per-QSO
    private func cacheServiceConfiguration() {
        qrzConfigured = (try? KeychainHelper.shared.read(for: KeychainHelper.Keys.qrzApiKey)) != nil
        potaConfigured =
            (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.potaUsername)) != nil
                && (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.potaPassword)) != nil
        lofiConfigured = UserDefaults.standard.bool(forKey: "lofi.deviceLinked")
        clublogConfigured =
            (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.clublogEmail)) != nil
                && (try? KeychainHelper.shared.readString(
                    for: KeychainHelper.Keys.clublogApiKey
                )) != nil
    }

    /// Detect and report notable activities for a newly logged QSO.
    /// Runs async and never blocks the logger.
    private func processActivityForQSO(_ qso: QSO) async {
        let aliasService = CallsignAliasService.shared
        guard let userCallsign = aliasService.getCurrentCallsign(), !userCallsign.isEmpty else {
            return
        }

        let detector = ActivityDetector(modelContext: modelContext, userCallsign: userCallsign)
        let detected = detector.detectActivities(for: [qso])

        guard !detected.isEmpty else {
            return
        }

        // Save local activity items
        detector.createActivityItems(from: detected)

        // Report to server (fire and forget, errors silently logged)
        let reporter = ActivityReporter()
        await reporter.reportActivities(detected, sourceURL: "https://activities.carrierwave.app")

        // Notify UI of new activities
        NotificationCenter.default.post(
            name: .didDetectActivities,
            object: nil,
            userInfo: ["count": detected.count]
        )
    }

    private func markForUpload(_ qso: QSO) {
        // Skip upload markers for metadata pseudo-modes (WEATHER, SOLAR, NOTE)
        // These are activation metadata from Ham2K PoLo, not actual QSOs
        guard !Self.metadataModes.contains(qso.mode.uppercased()) else {
            return
        }

        // Use cached service configuration (checked at session start)
        if qrzConfigured {
            qso.markNeedsUpload(to: .qrz, context: modelContext)
        }

        // POTA (only if this is a POTA activation, use cached value)
        if activeSession?.activationType == .pota,
           potaConfigured
        {
            qso.markNeedsUpload(to: .pota, context: modelContext)
        }

        // LoFi (use cached value)
        if lofiConfigured {
            qso.markNeedsUpload(to: .lofi, context: modelContext)
        }

        // Club Log (use cached value)
        if clublogConfigured {
            qso.markNeedsUpload(to: .clublog, context: modelContext)
        }
    }
}

// MARK: - SessionNoteEntry

/// A parsed note entry from session notes
struct SessionNoteEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let displayTime: String
    let text: String

    /// Parse a note line in format "[ISO8601|HH:mm] text" or legacy "[HH:mm] text"
    static func parse(_ line: String) -> SessionNoteEntry? {
        // Try new format first: [ISO8601|HH:mm] text
        if let bracketEnd = line.firstIndex(of: "]"),
           line.first == "["
        {
            let bracketContent = String(line[line.index(after: line.startIndex) ..< bracketEnd])
            let text = String(line[line.index(after: bracketEnd)...]).trimmingCharacters(
                in: .whitespaces
            )

            // Check for new format with pipe separator
            if let pipeIndex = bracketContent.firstIndex(of: "|") {
                let isoString = String(bracketContent[..<pipeIndex])
                let displayTime = String(bracketContent[bracketContent.index(after: pipeIndex)...])

                let isoFormatter = ISO8601DateFormatter()
                if let timestamp = isoFormatter.date(from: isoString) {
                    return SessionNoteEntry(
                        timestamp: timestamp,
                        displayTime: displayTime,
                        text: text
                    )
                }
            }

            // Legacy format: [HH:mm] text - use today's date with that time
            let displayTime = bracketContent
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = TimeZone(identifier: "UTC")

            // For legacy notes, we can't determine the exact date, so use a very old date
            // This will sort them before any new-format notes from today
            if let timeComponents = formatter.date(from: displayTime) {
                let calendar = Calendar.current
                // Use the time components with a base date of 1970
                var components = calendar.dateComponents([.hour, .minute], from: timeComponents)
                components.year = 1_970
                components.month = 1
                components.day = 1
                if let legacyDate = calendar.date(from: components) {
                    return SessionNoteEntry(
                        timestamp: legacyDate,
                        displayTime: displayTime,
                        text: text
                    )
                }
            }
        }

        return nil
    }
}

// MARK: - SessionLogEntry

/// A unified entry in the session log (either a QSO or a note)
enum SessionLogEntry: Identifiable {
    case qso(QSO)
    case note(SessionNoteEntry)

    // MARK: Internal

    var id: String {
        switch self {
        case let .qso(qso):
            "qso-\(qso.id)"
        case let .note(note):
            "note-\(note.id)"
        }
    }

    var timestamp: Date {
        switch self {
        case let .qso(qso):
            qso.timestamp
        case let .note(note):
            note.timestamp
        }
    }

    /// Combine QSOs and notes into a sorted list
    static func combine(qsos: [QSO], notes: [SessionNoteEntry]) -> [SessionLogEntry] {
        var entries: [SessionLogEntry] = []

        entries.append(contentsOf: qsos.map { .qso($0) })
        entries.append(contentsOf: notes.map { .note($0) })

        // Sort by timestamp, most recent first
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
}
