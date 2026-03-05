import CarrierWaveData
import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - LoggingSessionManager

/// Manages logging session lifecycle and QSO creation
@MainActor
@Observable
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

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    /// These should never be synced to any service
    static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Currently active session
    /// Note: internal setter needed for extension files that manage session lifecycle
    var activeSession: LoggingSession?

    /// Service for managing Live Activity on lock screen / Dynamic Island
    let liveActivityService = LiveActivityService()

    /// Service for polling POTA spot comments
    let spotCommentsService = SpotCommentsService()

    /// Service for monitoring RBN/POTA spots during session
    let spotMonitoringService = SpotMonitoringService()

    /// Friend callsigns for spot notifications -- set by the hosting view
    var friendCallsigns: Set<String> = []

    /// WebSDR recording session (optional, user-initiated)
    let webSDRSession = WebSDRSession()

    let modelContext: ModelContext

    /// Timer for auto-spotting to POTA (accessed by +Spotting extension)
    var autoSpotTimer: Timer?

    /// Auto-spot interval (10 minutes) (accessed by +Spotting extension)
    let autoSpotInterval: TimeInterval = 10 * 60

    /// Track which spot comment IDs have been attached to QSOs (accessed by +Spotting extension)
    var attachedSpotCommentIds: Set<Int64> = []

    /// Cached service configuration (checked once at session start to avoid Keychain reads per-QSO)
    var qrzConfigured = false
    var potaConfigured = false
    var lofiConfigured = false
    var clublogConfigured = false

    /// Key for storing active session ID in UserDefaults
    let activeSessionIdKey = "activeLoggingSessionId"

    /// Whether there's an active session
    var hasActiveSession: Bool {
        activeSession != nil
    }

    /// Whether to keep screen on during active session (from settings)
    /// Defaults to true if the setting hasn't been explicitly set (matches @AppStorage default)
    var keepScreenOn: Bool {
        if UserDefaults.standard.object(forKey: "loggerKeepScreenOn") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "loggerKeepScreenOn")
    }

    /// Start a new logging session
    func startSession(
        myCallsign: String,
        mode: String,
        frequency: Double? = nil,
        programs: Set<String> = [],
        activationType: ActivationType = .casual,
        parkReference: String? = nil,
        sotaReference: String? = nil,
        missionReference: String? = nil,
        wwffReference: String? = nil,
        myGrid: String? = nil,
        power: Int? = nil,
        myRig: String? = nil,
        myAntenna: String? = nil,
        myKey: String? = nil,
        myMic: String? = nil,
        extraEquipment: String? = nil,
        attendees: String? = nil,
        isRove: Bool = false,
        autoStartSDR: Bool = false
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
            programs: programs,
            activationType: activationType,
            parkReference: parkReference.flatMap { ParkReference.sanitizeMulti($0) },
            sotaReference: sotaReference,
            missionReference: missionReference,
            wwffReference: wwffReference,
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
        if isRove, session.isPOTA, let park = session.parkReference {
            session.isRove = true
            let firstStop = RoveStop(
                parkReference: park,
                startedAt: session.startedAt,
                myGrid: myGrid
            )
            session.roveStops = [firstStop]
        }

        session.cloudDirtyFlag = true
        modelContext.insert(session)
        activeSession = session
        saveActiveSessionId(session.id)

        activateSession(session, autoStartSDR: autoStartSDR)
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

        // Create new stop -- fall back to session grid if no grid provided
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
        updateLiveActivity()

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

    // MARK: Private

    /// Post-insert session activation: caching, timers, peripherals, and save.
    private func activateSession(_ session: LoggingSession, autoStartSDR: Bool) {
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

        // Connect BLE radio if configured
        connectBLERadio()

        // Auto-record solar/weather conditions
        recordConditions()

        try? modelContext.save()

        writeSessionToWidget(session)
        startLiveActivity()

        // Auto-start WebSDR if requested
        if autoStartSDR {
            autoStartWebSDR(session: session)
        }
    }

    /// Load active session from persisted ID
    private func loadActiveSession() {
        guard let idString = UserDefaults.standard.string(forKey: activeSessionIdKey),
              let sessionId = UUID(uuidString: idString)
        else {
            // No active session -- clean up any orphaned Live Activities
            liveActivityService.cleanupStale()
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
                // Reconnect to existing Live Activity, or start a new one
                if !liveActivityService.reconnect() {
                    startLiveActivity()
                }
                // Restart auto-spot timer for restored POTA session
                startAutoSpotTimer()
                // Restart spot comments polling for restored POTA session
                startSpotCommentsPolling()
                // Restart spot monitoring for restored session
                startSpotMonitoring()
                // Reconnect BLE radio for restored session
                connectBLERadio()
            } else {
                // Session was ended or not found, clear the stored ID
                clearActiveSessionId()
                liveActivityService.cleanupStale()
            }
        } catch {
            clearActiveSessionId()
            liveActivityService.cleanupStale()
        }
    }

    /// Auto-connect to the last-used KiwiSDR receiver when starting a session.
    private func autoStartWebSDR(session: LoggingSession) {
        let hostPort = UserDefaults.standard.string(forKey: "sdrLastReceiverHostPort") ?? ""
        guard !hostPort.isEmpty else {
            return
        }

        let parts = hostPort.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let port = Int(parts[1])
        else {
            return
        }

        let host = String(parts[0])
        let name = UserDefaults.standard.string(forKey: "sdrLastReceiverName") ?? hostPort

        let receiver = KiwiSDRReceiver(
            id: hostPort,
            name: name,
            host: host,
            port: port,
            latitude: 0,
            longitude: 0,
            bands: "",
            users: 0,
            maxUsers: 1,
            location: "",
            antenna: ""
        )

        guard let freq = session.frequency else {
            return
        }
        let mode = session.mode
        let sessionId = session.id

        Task {
            await webSDRSession.start(
                receiver: receiver,
                frequencyMHz: freq,
                mode: mode,
                loggingSessionId: sessionId,
                modelContext: modelContext
            )
        }
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
}
