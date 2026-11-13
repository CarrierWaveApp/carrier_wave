// TOTA-specific session lifecycle helpers:
//   - `TOTASessionOptions` carries the new-session inputs (activation lat/lon,
//     scoring bonuses, track-recording toggle) without bloating
//     `startSession`'s parameter list further.
//   - `applyTOTAOptions(_:to:)` copies those inputs onto the model.
//   - `flushTrackPoints(to:)` snapshots the recorded GPS track and the
//     derived distance / elevation gain back onto the session at end/pause.

import CarrierWaveData
import Foundation

// MARK: - TOTASessionOptions

struct TOTASessionOptions {
    var activationLatitude: Double?
    var activationLongitude: Double?
    var recordTrack: Bool = true
    var qrpActivation: Bool = false
    var withPets: Bool = false
    var withKids: Bool = false
    var winlinkSent: Bool = false
    var aprsSent: Bool = false
    var varacSent: Bool = false
    var adaptiveSport: Bool = false
    var ruckWeightPounds: Double?
    /// Standard or Mobile (Q9). Defaults to Standard.
    var category: TOTACategory = .standard
    /// 1...10 or nil (not opted in). Frozen onto the session at start.
    var personalEffortFactor: Int?
    /// nil = auto-detect from hemisphere+date; Bool = explicit user choice.
    var winterActivationOverride: Bool?
}

extension LoggingSessionManager {
    /// Whether there's an active session.
    var hasActiveSession: Bool {
        activeSession != nil
    }

    /// Whether to keep the screen on during an active session. Defaults to
    /// `true` when the setting hasn't been explicitly written (matches the
    /// `@AppStorage` default the Settings UI uses).
    var keepScreenOn: Bool {
        if UserDefaults.standard.object(forKey: "loggerKeepScreenOn") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "loggerKeepScreenOn")
    }

    func applyTOTAOptions(_ options: TOTASessionOptions, to session: LoggingSession) {
        session.activationLatitude = options.activationLatitude
        session.activationLongitude = options.activationLongitude
        session.qrpActivation = options.qrpActivation
        session.withPets = options.withPets
        session.withKids = options.withKids
        session.winlinkSent = options.winlinkSent
        session.aprsSent = options.aprsSent
        session.varacSent = options.varacSent
        session.adaptiveSport = options.adaptiveSport
        session.ruckWeightPounds = options.ruckWeightPounds
        session.totaCategory = options.category
        session.personalEffortFactor = options.personalEffortFactor
        session.winterActivationOverride = options.winterActivationOverride
    }

    /// Stop tracking (if running) and persist the recorded points + computed
    /// distance and elevation gain back to the session. Idempotent — safe to
    /// call on session end, pause, and resume cycles.
    func flushTrackPoints(to session: LoggingSession) {
        guard session.activationType == .tota else {
            return
        }
        let points = locationTrackingService.stop()
        guard !points.isEmpty else {
            return
        }
        session.trackPoints = points
        // Only override existing manual values when the track produced something
        // meaningful; user-entered numbers stick if they tracked a 0-mile walk.
        let distance = LocationTrackingService.totalDistanceMiles(in: points)
        if distance > 0 {
            session.activationDistanceMiles = distance
        }
        let gain = LocationTrackingService.totalElevationGainFeet(in: points)
        if gain > 0 {
            session.activationElevationGainFeet = gain
        }
    }

    /// Recompute the activated/candidate tile cache and refresh the T3 spot
    /// snapshot at session end. Best-effort — failures (offline, rate-limited)
    /// leave the cached snapshot untouched. Caller passes session QSOs so this
    /// helper doesn't reach into ModelContext.
    func enrichTOTAAtSessionEnd(
        session: LoggingSession,
        qsos: [QSO],
        client: TOTAClient = .shared
    ) async {
        guard session.activationType == .tota else {
            return
        }
        _ = TOTAEnrichmentService.recomputeTiles(for: session, qsos: qsos)
        await TOTAEnrichmentService.refreshT3Snapshot(
            for: session,
            qsos: qsos,
            client: client
        )
    }
}
