import CarrierWaveData
import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - FrequencyUpdateResult

/// Result of a frequency update on a logging session
struct FrequencyUpdateResult {
    /// Whether a QSY spot prompt should be shown
    let shouldPromptForSpot: Bool
    /// Suggested mode for the new frequency (nil if no change needed)
    let suggestedMode: String?
    /// Whether this was the first frequency set on a hunt-first session
    let isFirstFrequencySet: Bool
}

// MARK: - LoggingSessionManager

/// Manages logging session lifecycle and QSO creation
@MainActor
@Observable
final class LoggingSessionManager {
    // MARK: Lifecycle

    init(
        modelContext: ModelContext,
        locationService: LocationSessionService = LocationSessionService(),
        potaAuthService: POTAAuthService? = nil
    ) {
        self.modelContext = modelContext
        self.locationService = locationService
        self.potaAuthService = potaAuthService
        loadActiveSession()
        startContinuityObservation()
    }

    // MARK: Internal

    /// Currently active session
    /// Note: internal setter needed for extension files that manage session lifecycle
    var activeSession: LoggingSession?

    /// Shared location service for continuous grid tracking
    let locationService: LocationSessionService

    /// GPS track recorder for TOTA distance/elevation scoring. Idle unless a
    /// TOTA session is started with `TOTASessionOptions.recordTrack = true`.
    let locationTrackingService = LocationTrackingService()

    /// Service for managing Live Activity on lock screen / Dynamic Island
    let liveActivityService = LiveActivityService()

    /// Service for polling POTA spot comments
    let spotCommentsService = SpotCommentsService()

    /// Service for monitoring RBN/POTA spots during session
    let spotMonitoringService = SpotMonitoringService()

    /// Friend callsigns for spot notifications -- set by the hosting view
    var friendCallsigns: Set<String> = []

    /// Shared POTA auth service — avoids creating fresh WKWebView per spot post
    var potaAuthService: POTAAuthService?

    /// WebSDR recording session (optional, user-initiated)
    let webSDRSession = WebSDRSession()

    let modelContext: ModelContext

    /// Timer that fires at the next UTC midnight to split POTA sessions
    var utcMidnightTimer: Timer?

    /// QSO count from the previous UTC day's activation (set after a day rollover)
    var previousDayQSOCount: Int?

    /// Timer for auto-spotting to POTA (accessed by +Spotting extension)
    var autoSpotTimer: Timer?

    /// Auto-spot interval in seconds, overridable via SPOT REPEAT command (default 10 min)
    var autoSpotInterval: TimeInterval = 10 * 60

    /// Custom spot message set via SPOT <message> REPEAT <N> command (nil = no custom message)
    var customSpotMessage: String?

    /// Track which spot comment IDs have been attached to QSOs (accessed by +Spotting extension)
    var attachedSpotCommentIds: Set<Int64> = []

    /// In-memory dedup keys for recorded session spots (avoids unbounded SwiftData fetch)
    var recordedSpotDedupKeys: Set<String> = []

    /// Cached service configuration (checked once at session start to avoid Keychain reads per-QSO)
    var qrzConfigured = false
    var potaConfigured = false
    var lofiConfigured = false
    var clublogConfigured = false

    /// Key for storing active session ID in UserDefaults
    let activeSessionIdKey = "activeLoggingSessionId"

    // `hasActiveSession` and `keepScreenOn` live in LoggingSessionManager+TOTA.swift
    // to keep the class body under SwiftLint's 300-line cap.

    // swiftlint:disable function_body_length
    /// Start a new logging session.
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
        autoStartSDR: Bool = false,
        contestId: String? = nil,
        contestCategory: String? = nil,
        contestOverlayCategory: String? = nil,
        contestPower: String? = nil,
        contestBands: String? = nil,
        contestOperator: String? = nil,
        stationCallsign: String? = nil,
        operatorCallsigns: [String] = [],
        totaOptions: TOTASessionOptions? = nil,
        radioItemID: UUID? = nil
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
            attendees: attendees,
            contestId: contestId,
            contestCategory: contestCategory,
            contestOverlayCategory: contestOverlayCategory,
            contestPower: contestPower,
            contestBands: contestBands,
            contestOperator: contestOperator,
            stationCallsign: stationCallsign
        )

        resolveSessionGrid(
            session: session,
            sotaReference: sotaReference,
            parkReference: parkReference
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

        if !operatorCallsigns.isEmpty {
            session.operatorCallsigns = operatorCallsigns
        }
        if let totaOptions, activationType == .tota {
            applyTOTAOptions(totaOptions, to: session)
        }
        if let radioItemID {
            session.radioItemID = radioItemID
        }
        session.cloudDirtyFlag = true
        modelContext.insert(session)
        activeSession = session
        saveActiveSessionId(session.id)
        // Project the new session into cw-store at creation so the Rust-canonical
        // active-session pointer (`SessionApi.currentSession()`) resolves it
        // immediately — launch restore and the logger's Rust reads depend on the
        // row existing at start, not lazily on the first logged QSO. No-op when
        // the mirror is inactive (`CwStoreQSOMode.off`).
        try? EntityWriteSink.commitUpsert(session, in: modelContext)

        activateSession(session, autoStartSDR: autoStartSDR)
        locationService.start()
        if activationType == .tota, totaOptions?.recordTrack == true {
            locationTrackingService.start()
        }
    }

    // swiftlint:enable function_body_length

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

        try? EntityWriteSink.commitUpsert(session, in: modelContext)
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

    /// Observe location service grid changes and update the active session.
    /// Internal (not private) so extension files can call it on resume.
    func startGridObservation() {
        observeGridChanges()
    }

    func observeGridChanges() {
        withObservationTracking {
            _ = self.locationService.currentGrid
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let session = activeSession else {
                    return
                }
                if let newGrid = locationService.currentGrid,
                   newGrid != session.myGrid
                {
                    session.myGrid = newGrid
                    session.cloudDirtyFlag = true
                    try? EntityWriteSink.commitUpsert(session, in: modelContext)
                }
                // Re-register for the next change
                observeGridChanges()
            }
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

        // Start UTC midnight timer for POTA day boundary detection
        startUTCMidnightTimer()

        // Start spot comments polling for POTA activations
        startSpotCommentsPolling()

        // Start spot monitoring
        startSpotMonitoring()

        // Connect radio if configured
        connectRadio()

        // Auto-record solar/weather conditions
        recordConditions()

        // Observe GPS grid changes and update session
        startGridObservation()

        try? EntityWriteSink.commitUpsert(session, in: modelContext)

        writeSessionToWidget(session)
        startLiveActivity()

        // Auto-start WebSDR if requested
        if autoStartSDR {
            autoStartWebSDR(session: session)
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
}

// MARK: - Service Configuration Cache

extension LoggingSessionManager {
    /// Cache service configuration to avoid Keychain reads per-QSO.
    /// Uses ServiceConfiguration for QRZ/POTA to stay consistent with ADIF import path.
    func cacheServiceConfiguration() {
        let configured = CarrierWaveData.ServiceConfiguration.configuredUploadServices()
        qrzConfigured = configured.contains(.qrz)
        potaConfigured = configured.contains(.pota)
        lofiConfigured = UserDefaults.standard.bool(forKey: "lofi.deviceLinked")
        clublogConfigured =
            (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.clublogEmail)) != nil
                && (try? KeychainHelper.shared.readString(
                    for: KeychainHelper.Keys.clublogPassword
                )) != nil
                && (try? KeychainHelper.shared.readString(
                    for: KeychainHelper.Keys.clublogCallsign
                )) != nil
    }
}
