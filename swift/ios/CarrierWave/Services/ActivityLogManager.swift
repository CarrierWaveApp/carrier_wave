import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData
import SwiftUI

// MARK: - ActivityLogManager

/// Manages activity log lifecycle and QSO creation for the "hunter" workflow.
/// Unlike LoggingSessionManager (activation-centric), this handles persistent,
/// always-open logging with daily QSO tracking and incremental uploads.
@MainActor
@Observable
final class ActivityLogManager {
    // MARK: Lifecycle

    init(modelContext: ModelContext, locationService: LocationSessionService = LocationSessionService()) {
        self.modelContext = modelContext
        self.locationService = locationService
        loadActiveLog()
        refreshCurrentProfile()
        // cacheServiceConfiguration() deferred to first markForUpload() call
        // to avoid 3 synchronous Keychain reads blocking the main thread.

        // Start location tracking if active profile uses current location
        if activeLog != nil, currentProfile?.useCurrentLocation == true {
            locationService.start()
            startGridObservation()
        }
    }

    // MARK: Internal

    /// UserDefaults key for persisting active log ID across launches.
    /// Internal so `+Persistence` (separate file) can reach it.
    static let activeLogIdKey = "activeActivityLogId"

    /// Currently active activity log.
    /// Internal set (not `private(set)`) so `+Persistence` can restore it.
    var activeLog: ActivityLog?

    /// Today's QSO count (updated on log and on load).
    /// Internal set (not `private(set)`) so `+RustDelegation` can refresh it.
    var todayQSOCount: Int = 0

    /// Today's bands worked
    var todayBands: Set<String> = []

    /// Today's modes used
    var todayModes: Set<String> = []

    /// Whether the daily goal was just reached (reset after consuming)
    var dailyGoalReached = false

    /// Cached current profile (refreshed on profile changes)
    private(set) var currentProfile: StationProfile?

    let modelContext: ModelContext

    /// Shared location service for continuous grid tracking
    let locationService: LocationSessionService

    /// Daily QSO goal (0 = disabled)
    @ObservationIgnored
    var dailyGoal: Int {
        get {
            guard UserDefaults.standard.bool(forKey: "activityLogDailyGoalEnabled") else {
                return 0
            }
            return UserDefaults.standard.integer(forKey: "activityLogDailyGoal")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "activityLogDailyGoal")
        }
    }

    /// Whether there's an active activity log
    var hasActiveLog: Bool {
        activeLog != nil
    }

    /// The shared hunter API, but only when cw-store is authoritative (`.on`).
    /// Used by `+RustDelegation` + `refreshTodayStats`.
    var hunterApi: ActivityLogApi? {
        guard CwStoreQSOMode.current == .on else {
            return nil
        }
        return ActivityLogApiRegistry.current
    }

    /// Reload the current profile from storage (call after profile changes)
    func refreshCurrentProfile() {
        if let profileId = activeLog?.stationProfileId,
           let profile = StationProfileStorage.profile(for: profileId)
        {
            currentProfile = profile
        } else {
            currentProfile = StationProfileStorage.defaultProfile()
        }
    }

    // MARK: - Log Lifecycle

    /// Create and activate a new activity log
    func createLog(name: String, myCallsign: String, profileId: UUID? = nil) {
        // Deactivate any existing active log
        let previous = activeLog
        previous?.isActive = false
        previous?.cloudDirtyFlag = true

        let log = ActivityLog(
            name: name,
            myCallsign: myCallsign,
            stationProfileId: profileId ?? StationProfileStorage.defaultProfile()?.id,
            isActive: true
        )

        // Set grid from profile if available (skip for location-based profiles)
        if let profile = currentProfile, !profile.useCurrentLocation {
            log.currentGrid = profile.grid
        }

        log.cloudDirtyFlag = true
        modelContext.insert(log)
        activeLog = log
        saveActiveLogId(log.id)
        try? EntityWriteSink.commitUpsert([previous, log].compactMap { $0 }, in: modelContext)

        refreshCurrentProfile()
        refreshTodayStats()

        if currentProfile?.useCurrentLocation == true {
            locationService.start()
            startGridObservation()
        }
    }

    /// Activate an existing activity log
    func activateLog(_ log: ActivityLog) {
        let previous = activeLog.flatMap { $0.id != log.id ? $0 : nil }
        previous?.isActive = false
        previous?.cloudDirtyFlag = true
        log.isActive = true
        log.cloudDirtyFlag = true
        activeLog = log
        saveActiveLogId(log.id)
        cacheServiceConfiguration()
        try? EntityWriteSink.commitUpsert([previous, log].compactMap { $0 }, in: modelContext)

        refreshCurrentProfile()
        refreshTodayStats()

        if currentProfile?.useCurrentLocation == true {
            locationService.start()
            startGridObservation()
        }
    }

    /// Deactivate the current activity log (does not delete it)
    func deactivateLog() {
        guard let log = activeLog else {
            return
        }
        log.isActive = false
        log.cloudDirtyFlag = true
        activeLog = nil
        clearActiveLogId()
        locationService.stop()
        try? EntityWriteSink.commitUpsert(log, in: modelContext)
    }

    /// Delete an activity log (QSOs remain, only the log record is removed)
    func deleteLog(_ log: ActivityLog) {
        if activeLog?.id == log.id {
            locationService.stop()
            activeLog = nil
            clearActiveLogId()
        }
        try? EntityWriteSink.commitDelete(log, in: modelContext)
    }

    /// Switch the station profile for the active log
    func switchProfile(_ profile: StationProfile) {
        guard let log = activeLog else {
            return
        }

        // Stop location if old profile used it
        if currentProfile?.useCurrentLocation == true {
            locationService.stop()
        }

        log.stationProfileId = profile.id
        if !profile.useCurrentLocation, let grid = profile.grid {
            log.currentGrid = grid
        }
        log.cloudDirtyFlag = true
        try? EntityWriteSink.commitUpsert(log, in: modelContext)
        refreshCurrentProfile()

        // Start location if new profile uses it
        if profile.useCurrentLocation {
            locationService.start()
            startGridObservation()
        }
    }

    /// Update the current grid square
    func updateGrid(_ grid: String) {
        guard let log = activeLog else {
            return
        }
        log.currentGrid = grid
        log.cloudDirtyFlag = true
        try? EntityWriteSink.commitUpsert(log, in: modelContext)
    }

    /// Update the location label
    func updateLocationLabel(_ label: String?) {
        guard let log = activeLog else {
            return
        }
        log.locationLabel = label
        log.cloudDirtyFlag = true
        try? EntityWriteSink.commitUpsert(log, in: modelContext)
    }

    // MARK: - QSO Logging

    // swiftlint:disable function_body_length

    /// Log a new QSO from the activity log
    func logQSO(
        callsign: String,
        band: String,
        mode: String,
        frequency: Double? = nil,
        rstSent: String = "599",
        rstReceived: String = "599",
        theirGrid: String? = nil,
        theirParkReference: String? = nil,
        sotaRef: String? = nil,
        notes: String? = nil,
        name: String? = nil,
        state: String? = nil,
        country: String? = nil
    ) -> LoggedQSO? {
        guard let log = activeLog else {
            return nil
        }

        let profile = currentProfile

        // Under `.on`, delegate to the shared Rust `ActivityLogApi` (see
        // `+RustDelegation`); falls through to the SwiftData path in `.off`/`.shadow`.
        if let logged = logQSOViaRustIfEnabled(
            callsign: callsign, band: band, mode: mode,
            frequency: frequency, rstSent: rstSent, rstReceived: rstReceived,
            theirGrid: theirGrid, theirPark: theirParkReference, sotaRef: sotaRef,
            notes: notes, name: name, state: state, country: country
        ) {
            return logged
        }

        let qso = QSO(
            callsign: callsign.uppercased(),
            band: band,
            mode: mode,
            frequency: frequency,
            timestamp: Date(),
            rstSent: rstSent,
            rstReceived: rstReceived,
            myCallsign: log.myCallsign,
            myGrid: log.currentGrid,
            theirGrid: theirGrid,
            theirParkReference: theirParkReference,
            notes: notes,
            // Notes came from the user's quick-entry form — tag as user-authored. CAR-243.
            notesUserAuthored: notes?.isEmpty == false,
            importSource: .logger,
            name: name,
            state: state,
            country: country,
            power: profile?.power,
            myRig: profile?.rig,
            stationProfileName: profile?.name,
            sotaRef: sotaRef
        )

        // Link QSO to this activity log via loggingSessionId
        qso.loggingSessionId = log.id
        qso.isActivityLogQSO = true
        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()

        modelContext.insert(qso)
        markForUpload(qso)
        try? modelContext.save()
        QSOLedger.append(qso)

        NotificationCenter.default.post(
            name: .didLogQSO,
            object: nil,
            userInfo: ["callsign": qso.callsign]
        )

        // Update today's stats
        todayQSOCount += 1
        todayBands.insert(band)
        todayModes.insert(mode)

        // Check daily goal
        if dailyGoal > 0, todayQSOCount == dailyGoal {
            dailyGoalReached = true
        }

        // Detect activities (new DXCC, new band, DX contact, etc.)
        detectActivities(for: qso)

        return LoggedQSO(qso: qso)
    }

    // swiftlint:enable function_body_length

    /// Consume the daily goal reached flag (call after showing toast)
    func consumeDailyGoalReached() {
        dailyGoalReached = false
    }

    /// Mark QSO for upload to QRZ and LoFi only (never POTA)
    func markForUpload(_ qso: QSO) {
        // Lazy-load service config on first QSO log to avoid
        // blocking init() with synchronous Keychain reads.
        if !hasLoadedServiceConfig {
            cacheServiceConfiguration()
            hasLoadedServiceConfig = true
        }

        // Skip metadata pseudo-modes
        guard !QSOMode.isMetadata(qso.mode) else {
            return
        }

        if qrzConfigured {
            qso.markNeedsUpload(to: .qrz, context: modelContext)
        }

        // Activity log QSOs never go to POTA (no operator park reference)

        if lofiConfigured {
            qso.markNeedsUpload(to: .lofi, context: modelContext)
        }

        if clublogConfigured {
            qso.markNeedsUpload(to: .clublog, context: modelContext)
        }
    }

    // MARK: Private

    /// Cached service configuration (loaded lazily on first QSO log)
    private var qrzConfigured = false
    private var lofiConfigured = false
    private var clublogConfigured = false
    private var hasLoadedServiceConfig = false

    private func todayStartUTC() -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: Date())
    }

    /// Cache service configuration to avoid Keychain reads per-QSO.
    /// Uses ServiceConfiguration for QRZ to stay consistent with ADIF import path.
    private func cacheServiceConfiguration() {
        qrzConfigured = CarrierWaveData.ServiceConfiguration.isConfigured(.qrz)
        lofiConfigured = UserDefaults.standard.bool(forKey: "lofi.deviceLinked")
        clublogConfigured =
            (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.clublogEmail
            )) != nil
            && (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.clublogPassword
            )) != nil
            && (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.clublogCallsign
            )) != nil
    }
}

// MARK: - Stats

extension ActivityLogManager {
    /// Refresh today's QSO statistics from the database
    func refreshTodayStats() {
        guard let log = activeLog else {
            todayQSOCount = 0
            todayBands = []
            todayModes = []
            return
        }

        // Under `.on`, source today-stats from the shared core (same aggregation as
        // Android) instead of the SwiftData scan below.
        // cw-store ids are lowercase (SwiftDataStoreImporter.uuid), not `uuidString`.
        if let api = hunterApi, let stats = try? api.todayStats(logId: SwiftDataStoreImporter.uuid(log.id)) {
            todayQSOCount = Int(stats.qsoCount)
            todayBands = Set(stats.bands)
            todayModes = Set(stats.modes)
            return
        }

        let logId = log.id
        let startOfDay = todayStartUTC()

        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == logId
                && !qso.isHidden
                && qso.timestamp >= startOfDay
        }

        let descriptor = BoundedDescriptor<QSO>(
            predicate: predicate, limit: 500
        )

        do {
            let qsos = try modelContext.boundedFetch(descriptor)
            todayQSOCount = qsos.count
            todayBands = Set(qsos.map(\.band))
            todayModes = Set(qsos.map(\.mode))
        } catch {
            todayQSOCount = 0
            todayBands = []
            todayModes = []
        }
    }

    /// Fetch today's recent QSOs for display
    func fetchRecentQSOs(limit: Int = 5) -> [QSO] {
        guard let log = activeLog else {
            return []
        }

        let logId = log.id
        let startOfDay = todayStartUTC()

        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == logId
                && !qso.isHidden
                && qso.timestamp >= startOfDay
        }

        let descriptor = BoundedDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
            limit: limit
        )

        return (try? modelContext.boundedFetch(descriptor)) ?? []
    }

    /// Get all activity logs
    func getAllLogs() -> [ActivityLog] {
        let descriptor = FetchDescriptor<ActivityLog>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Activity Detection

extension ActivityLogManager {
    /// Run activity detection for a newly logged QSO
    func detectActivities(for qso: QSO) {
        guard let callsign = activeLog?.myCallsign, !callsign.isEmpty else {
            return
        }
        let detector = ActivityDetector(
            modelContext: modelContext,
            userCallsign: callsign
        )
        let detected = detector.detectActivities(for: [qso])
        guard !detected.isEmpty else {
            return
        }
        detector.createActivityItems(from: detected)
    }
}
