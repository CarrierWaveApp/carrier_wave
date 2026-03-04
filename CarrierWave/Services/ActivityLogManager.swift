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

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadActiveLog()
        refreshCurrentProfile()
        // cacheServiceConfiguration() deferred to first markForUpload() call
        // to avoid 3 synchronous Keychain reads blocking the main thread.
    }

    // MARK: Internal

    /// Currently active activity log
    private(set) var activeLog: ActivityLog?

    /// Today's QSO count (updated on log and on load)
    private(set) var todayQSOCount: Int = 0

    /// Today's bands worked
    private(set) var todayBands: Set<String> = []

    /// Today's modes used
    private(set) var todayModes: Set<String> = []

    /// Whether the daily goal was just reached (reset after consuming)
    private(set) var dailyGoalReached = false

    /// Cached current profile (refreshed on profile changes)
    private(set) var currentProfile: StationProfile?

    let modelContext: ModelContext

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
        if let existing = activeLog {
            existing.isActive = false
            existing.cloudDirtyFlag = true
        }

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
        try? modelContext.save()

        refreshCurrentProfile()
        refreshTodayStats()
    }

    /// Activate an existing activity log
    func activateLog(_ log: ActivityLog) {
        if let existing = activeLog, existing.id != log.id {
            existing.isActive = false
            existing.cloudDirtyFlag = true
        }
        log.isActive = true
        log.cloudDirtyFlag = true
        activeLog = log
        saveActiveLogId(log.id)
        cacheServiceConfiguration()
        try? modelContext.save()

        refreshCurrentProfile()
        refreshTodayStats()
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
        try? modelContext.save()
    }

    /// Delete an activity log (QSOs remain, only the log record is removed)
    func deleteLog(_ log: ActivityLog) {
        if activeLog?.id == log.id {
            activeLog = nil
            clearActiveLogId()
        }
        modelContext.delete(log)
        try? modelContext.save()
    }

    /// Switch the station profile for the active log
    func switchProfile(_ profile: StationProfile) {
        guard let log = activeLog else {
            return
        }
        log.stationProfileId = profile.id
        if !profile.useCurrentLocation, let grid = profile.grid {
            log.currentGrid = grid
        }
        log.cloudDirtyFlag = true
        try? modelContext.save()
        refreshCurrentProfile()
    }

    /// Update the current grid square
    func updateGrid(_ grid: String) {
        guard let log = activeLog else {
            return
        }
        log.currentGrid = grid
        log.cloudDirtyFlag = true
        try? modelContext.save()
    }

    /// Update the location label
    func updateLocationLabel(_ label: String?) {
        guard let log = activeLog else {
            return
        }
        log.locationLabel = label
        log.cloudDirtyFlag = true
        try? modelContext.save()
    }

    // MARK: - QSO Logging

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
        notes: String? = nil,
        name: String? = nil,
        state: String? = nil,
        country: String? = nil
    ) -> QSO? {
        guard let log = activeLog else {
            return nil
        }

        let profile = currentProfile

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
            importSource: .logger,
            name: name,
            state: state,
            country: country,
            power: profile?.power,
            myRig: profile?.rig,
            stationProfileName: profile?.name
        )

        // Link QSO to this activity log via loggingSessionId
        qso.loggingSessionId = log.id
        qso.isActivityLogQSO = true
        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()

        modelContext.insert(qso)
        markForUpload(qso)
        try? modelContext.save()

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

        return qso
    }

    /// Consume the daily goal reached flag (call after showing toast)
    func consumeDailyGoalReached() {
        dailyGoalReached = false
    }

    // MARK: - Stats

    /// Refresh today's QSO statistics from the database
    func refreshTodayStats() {
        guard let log = activeLog else {
            todayQSOCount = 0
            todayBands = []
            todayModes = []
            return
        }

        let logId = log.id
        let startOfDay = todayStartUTC()

        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == logId
                && !qso.isHidden
                && qso.timestamp >= startOfDay
        }

        var descriptor = FetchDescriptor<QSO>(predicate: predicate)
        descriptor.fetchLimit = 500

        do {
            let qsos = try modelContext.fetch(descriptor)
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

        var descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Get all activity logs
    func getAllLogs() -> [ActivityLog] {
        let descriptor = FetchDescriptor<ActivityLog>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: Private

    /// Modes that represent activation metadata, not actual QSOs
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// UserDefaults key for persisting active log ID across launches
    private static let activeLogIdKey = "activeActivityLogId"

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

    /// Mark QSO for upload to QRZ and LoFi only (never POTA)
    private func markForUpload(_ qso: QSO) {
        // Lazy-load service config on first QSO log to avoid
        // blocking init() with synchronous Keychain reads.
        if !hasLoadedServiceConfig {
            cacheServiceConfiguration()
            hasLoadedServiceConfig = true
        }

        // Skip metadata pseudo-modes
        guard !Self.metadataModes.contains(qso.mode.uppercased()) else {
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

    /// Cache service configuration to avoid Keychain reads per-QSO
    private func cacheServiceConfiguration() {
        qrzConfigured = (try? KeychainHelper.shared.read(
            for: KeychainHelper.Keys.qrzApiKey
        )) != nil
        lofiConfigured = UserDefaults.standard.bool(forKey: "lofi.deviceLinked")
        clublogConfigured =
            (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.clublogEmail
            )) != nil
            && (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.clublogApiKey
            )) != nil
    }

    /// Load active log from persisted ID
    private func loadActiveLog() {
        guard let idString = UserDefaults.standard.string(
            forKey: Self.activeLogIdKey
        ),
            let logId = UUID(uuidString: idString)
        else {
            return
        }

        let predicate = #Predicate<ActivityLog> { log in
            log.id == logId
        }
        let descriptor = FetchDescriptor<ActivityLog>(predicate: predicate)

        do {
            let logs = try modelContext.fetch(descriptor)
            if let log = logs.first, log.isActive {
                activeLog = log
                // Today stats deferred to first refreshTodayStats() call
                // to avoid an expensive SwiftData query during init.
            } else {
                clearActiveLogId()
            }
        } catch {
            clearActiveLogId()
        }
    }

    private func saveActiveLogId(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeLogIdKey)
    }

    private func clearActiveLogId() {
        UserDefaults.standard.removeObject(forKey: Self.activeLogIdKey)
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
