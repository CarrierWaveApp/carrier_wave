// swiftlint:disable identifier_name file_length
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
    }

    /// Currently active session
    private(set) var activeSession: LoggingSession?

    /// Service for polling POTA spot comments
    let spotCommentsService = SpotCommentsService()

    /// Service for monitoring RBN/POTA spots during session
    let spotMonitoringService = SpotMonitoringService()

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
        myGrid: String? = nil
    ) {
        // End any existing session first
        if let existing = activeSession {
            existing.end()
        }

        let session = LoggingSession(
            myCallsign: myCallsign,
            startedAt: Date(),
            frequency: frequency,
            mode: mode,
            activationType: activationType,
            parkReference: parkReference,
            sotaReference: sotaReference,
            myGrid: myGrid
        )

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

        try? modelContext.save()
    }

    /// End the current session
    func endSession() {
        guard let session = activeSession else {
            return
        }

        session.end()
        activeSession = nil
        clearActiveSessionId()

        // Stop auto-spot timer
        stopAutoSpotTimer()

        // Stop spot comments polling
        spotCommentsService.stopPolling()
        spotCommentsService.clear()
        attachedSpotCommentIds = []

        // Stop spot monitoring
        spotMonitoringService.stopMonitoring()

        // Re-enable screen timeout
        UIApplication.shared.isIdleTimerDisabled = false

        try? modelContext.save()
    }

    /// Pause the current session
    func pauseSession() {
        guard let session = activeSession else {
            return
        }
        session.pause()

        // Stop auto-spot timer while paused
        stopAutoSpotTimer()

        // Pause spot comments polling
        spotCommentsService.stopPolling()

        // Pause spot monitoring
        spotMonitoringService.stopMonitoring()

        try? modelContext.save()
    }

    /// Resume a paused session
    func resumeSession() {
        guard let session = activeSession else {
            return
        }
        session.resume()

        // Restart auto-spot timer
        startAutoSpotTimer()

        // Restart spot comments polling
        startSpotCommentsPolling()

        // Restart spot monitoring
        startSpotMonitoring()

        try? modelContext.save()
    }

    /// Resume a specific session by ID
    func resumeSession(_ session: LoggingSession) {
        // End any existing active session
        if let existing = activeSession, existing.id != session.id {
            existing.end()
            stopAutoSpotTimer()
            spotCommentsService.stopPolling()
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
    func updateFrequency(_ frequency: Double) -> FrequencyUpdateResult {
        guard let session = activeSession else {
            return FrequencyUpdateResult(shouldPromptForSpot: false, suggestedMode: nil)
        }

        let oldFrequency = session.frequency
        session.updateFrequency(frequency)
        try? modelContext.save()

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
        // Don't prompt for spot if frequency is outside amateur bands or violates license
        var shouldPromptForSpot = false
        if session.activationType == .pota,
           oldFrequency != nil,
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
            suggestedMode: modeToSuggest
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

        // Return whether this is a QSY that could be spotted
        return session.activationType == .pota
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

        session.parkReference = parkReference?.uppercased()
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
            callsign: callsign.uppercased(),
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
            theirLicenseClass: theirLicenseClass
        )

        // Set the logging session ID
        qso.loggingSessionId = session.id

        modelContext.insert(qso)
        session.incrementQSOCount()

        // Mark for upload to configured services
        markForUpload(qso)

        try? modelContext.save()

        return qso
    }

    /// Hide a QSO (soft delete)
    func hideQSO(_ qso: QSO) {
        qso.isHidden = true
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
            }
        } catch {
            // Continue with session deletion even if QSO hiding fails
        }

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

    // MARK: Private

    private let modelContext: ModelContext

    /// Cached service configuration (checked once at session start to avoid Keychain reads per-QSO)
    private var qrzConfigured = false
    private var lofiConfigured = false

    /// Key for storing active session ID in UserDefaults
    private let activeSessionIdKey = "activeLoggingSessionId"

    /// Timer for auto-spotting to POTA
    private var autoSpotTimer: Timer?

    /// Auto-spot interval (10 minutes)
    private let autoSpotInterval: TimeInterval = 10 * 60

    /// Track which spot comment IDs have been attached to QSOs
    private var attachedSpotCommentIds: Set<Int64> = []

    /// Whether to keep screen on during active session (from settings)
    private var keepScreenOn: Bool {
        UserDefaults.standard.bool(forKey: "loggerKeepScreenOn")
    }

    /// Whether auto-spotting is enabled (from settings)
    private var potaAutoSpotEnabled: Bool {
        UserDefaults.standard.bool(forKey: "potaAutoSpotEnabled")
    }

    /// Start the auto-spot timer for POTA activations
    private func startAutoSpotTimer() {
        stopAutoSpotTimer()

        guard potaAutoSpotEnabled,
              let session = activeSession,
              session.activationType == .pota
        else {
            return
        }

        // Post an initial spot immediately
        Task {
            await postSpot()
        }

        // Schedule recurring spots every 10 minutes
        autoSpotTimer = Timer.scheduledTimer(
            withTimeInterval: autoSpotInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.postSpot()
            }
        }
    }

    /// Stop the auto-spot timer
    private func stopAutoSpotTimer() {
        autoSpotTimer?.invalidate()
        autoSpotTimer = nil
    }

    /// Start spot comments polling for POTA activations
    private func startSpotCommentsPolling() {
        guard let session = activeSession,
              session.activationType == .pota,
              let parkRef = session.parkReference
        else {
            return
        }

        let callsign = session.myCallsign
        guard !callsign.isEmpty else {
            return
        }

        spotCommentsService.onNewComments = { [weak self] comments in
            self?.attachSpotComments(comments)
        }

        spotCommentsService.startPolling(activator: callsign, parkRef: parkRef)
    }

    /// Attach spot comments to matching QSOs in the current session
    /// Matches by callsign and ±5 minute time window
    private func attachSpotComments(_ comments: [POTASpotComment]) {
        guard activeSession != nil else {
            return
        }

        let sessionQSOs = getSessionQSOs()
        guard !sessionQSOs.isEmpty else {
            return
        }

        for comment in comments {
            // Skip if already attached
            guard !attachedSpotCommentIds.contains(comment.spotId) else {
                continue
            }

            // Skip if no comment text
            guard let commentText = comment.comments, !commentText.isEmpty else {
                continue
            }

            guard let commentTimestamp = comment.timestamp else {
                continue
            }

            // Find matching QSO: same callsign, within ±5 minutes
            let spotter = comment.spotter.uppercased()
            let timeWindow: TimeInterval = 5 * 60 // 5 minutes

            for qso in sessionQSOs {
                let timeDiff = abs(qso.timestamp.timeIntervalSince(commentTimestamp))
                if qso.callsign.uppercased() == spotter, timeDiff <= timeWindow {
                    // Attach comment to QSO
                    let spotNote = "[Spot: \(comment.spotter)] \(commentText)"
                    if let existingNotes = qso.notes, !existingNotes.isEmpty {
                        qso.notes = "\(existingNotes) | \(spotNote)"
                    } else {
                        qso.notes = spotNote
                    }

                    attachedSpotCommentIds.insert(comment.spotId)
                    try? modelContext.save()

                    SyncDebugLog.shared.info(
                        "Attached spot comment from \(comment.spotter) to QSO with \(qso.callsign)",
                        service: .pota
                    )
                    break // Only attach to first matching QSO
                }
            }
        }
    }

    /// Start spot monitoring for the current session
    private func startSpotMonitoring() {
        guard let session = activeSession else {
            return
        }

        let callsign = session.myCallsign
        guard !callsign.isEmpty else {
            return
        }

        // Include POTA spots only for POTA activations
        let includePOTA = session.activationType == .pota

        spotMonitoringService.startMonitoring(
            callsign: callsign,
            myGrid: session.myGrid,
            includePOTA: includePOTA
        )
    }

    /// Post a spot to POTA (used for both auto-spots and QSY spots)
    private func postSpot(comment: String? = nil, showToast: Bool = false) async {
        guard let session = activeSession, session.activationType == .pota,
              let parkRef = session.parkReference, let freq = session.frequency,
              !session.myCallsign.isEmpty
        else {
            return
        }

        // Validate frequency is within amateur bands before spotting
        let violation = BandPlanService.validate(
            frequencyMHz: freq,
            mode: session.mode,
            license: .extra // Use most permissive for band boundary check
        )
        if let violation, violation.type == .outOfBand {
            SyncDebugLog.shared.warning(
                "Skipping spot: frequency \(FrequencyFormatter.format(freq)) is outside amateur bands",
                service: .pota
            )
            return
        }

        do {
            let potaClient = POTAClient(authService: POTAAuthService())
            _ = try await potaClient.postSpot(
                callsign: session.myCallsign, reference: parkRef,
                frequency: freq * 1_000, mode: session.mode, comments: comment
            )
            let msg = comment != nil ? "\(comment!) spot posted" : "Auto-spot posted"
            SyncDebugLog.shared.info("\(msg) for \(parkRef)", service: .pota)
            if showToast {
                ToastManager.shared.spotPosted(
                    park: parkRef, comment: "QSY to \(FrequencyFormatter.format(freq))"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Spot failed: \(error.localizedDescription)", service: .pota)
        }
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

    /// Mark QSO for upload to configured services
    /// Cache service configuration to avoid Keychain reads per-QSO
    private func cacheServiceConfiguration() {
        qrzConfigured = (try? KeychainHelper.shared.read(for: KeychainHelper.Keys.qrzApiKey)) != nil
        lofiConfigured = UserDefaults.standard.bool(forKey: "lofi.deviceLinked")
    }

    private func markForUpload(_ qso: QSO) {
        // Use cached service configuration (checked at session start)
        if qrzConfigured {
            qso.markNeedsUpload(to: .qrz, context: modelContext)
        }

        // POTA (only if this is a POTA activation)
        if activeSession?.activationType == .pota,
           UserDefaults.standard.bool(forKey: "pota.authenticated")
        {
            qso.markNeedsUpload(to: .pota, context: modelContext)
        }

        // LoFi (use cached value)
        if lofiConfigured {
            qso.markNeedsUpload(to: .lofi, context: modelContext)
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
