import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData
import UIKit

// MARK: - Shared Helpers

extension LoggingSessionManager {
    /// Save active session ID to UserDefaults
    func saveActiveSessionId(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeSessionIdKey)
    }

    /// Restore the active session at launch, all-in on Rust: the cw-store is
    /// canonical for *which* session is active. Ask `currentSession()` (which
    /// already filters `status = active AND endedAt IS NULL`, so no SwiftData
    /// healing is needed), reflect the row into the SwiftData replica, and adopt
    /// it. When the seam is unavailable (the `.off` kill switch / experiment off)
    /// or `currentSession()` errors, no session is restored — there is no
    /// SwiftData/`UserDefaults` restoration fallback.
    func loadActiveSession() {
        guard let api = sessionApi, let mirror = rustLogMirror else {
            liveActivityService.cleanupStale()
            return
        }
        do {
            guard let current = try api.currentSession() else {
                clearActiveSessionId()
                liveActivityService.cleanupStale()
                return
            }
            let session = try FfiReflector.reflect(current, into: modelContext, mirror: mirror)
            // Keep the UserDefaults cache in sync for the continuity layer.
            saveActiveSessionId(session.id)
            adoptRestoredSession(session)
        } catch {
            CwStoreWriteLog.shared.record("current session restore failed: \(error)")
            liveActivityService.cleanupStale()
        }
    }

    /// Wire up timers, peripherals, and Live Activity for a session restored
    /// from persisted state at app launch.
    private func adoptRestoredSession(_ session: LoggingSession) {
        activeSession = session
        cacheServiceConfiguration()
        if keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        if !liveActivityService.reconnect() {
            startLiveActivity()
        }
        startAutoSpotTimer()
        startUTCMidnightTimer()
        startSpotCommentsPolling()
        startSpotMonitoring()
        connectRadio()
        locationService.start()
        startGridObservation()
    }

    /// Populate `session.myGrid` at session-start time, in priority order:
    ///   1) any value already on the session (caller-provided)
    ///   2) SOTA summit surveyed coords (CAR-255)
    ///   3) POTA park surveyed coords (parity)
    ///   4) current GPS fix
    /// Surveyed coords beat GPS because GPS is unreliable at the moment of
    /// session start (cold fix, indoors, locked phone in a backpack).
    func resolveSessionGrid(
        session: LoggingSession,
        sotaReference: String?,
        parkReference: String?
    ) {
        if session.myGrid == nil, let sota = sotaReference {
            session.myGrid = gridFromSOTASummit(sota)
        }
        if session.myGrid == nil, let park = parkReference {
            session.myGrid = gridFromPOTAPark(park)
        }
        if session.myGrid == nil, let gpsGrid = locationService.currentGrid {
            session.myGrid = gpsGrid
        }
    }

    /// Resolve a SOTA reference (e.g. `W6/CT-225`) to a Maidenhead grid via
    /// the summit cache's surveyed coordinates. Honours the user's grid
    /// precision preference. Returns nil if the cache is cold for that
    /// summit, or if the row has no lat/lng.
    func gridFromSOTASummit(_ reference: String) -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty,
              let summit = SOTASummitsCache.shared.lookupSummit(trimmed),
              let lat = summit.latitude,
              let lon = summit.longitude
        else {
            return nil
        }
        return CarrierWaveCore.MaidenheadConverter.grid(
            from: Coordinate(latitude: lat, longitude: lon),
            precision: GridPrecisionPreference.current
        )
    }

    /// Resolve a POTA reference (e.g. `K-1234`) to a Maidenhead grid via the
    /// park cache's coordinates. Counterpart to `gridFromSOTASummit` so park
    /// activations get the same surveyed-grid treatment when GPS is unreliable
    /// at session start. The first reference in a multi-park (n-fer) string
    /// wins. Returns nil if the cache is cold or the row has no lat/lng.
    func gridFromPOTAPark(_ reference: String) -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespaces).uppercased()
        let primary = trimmed.split(separator: ",")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? trimmed
        guard !primary.isEmpty,
              let park = POTAParksCache.shared.parkSync(for: primary),
              let lat = park.latitude,
              let lon = park.longitude
        else {
            return nil
        }
        return CarrierWaveCore.MaidenheadConverter.grid(
            from: Coordinate(latitude: lat, longitude: lon),
            precision: GridPrecisionPreference.current
        )
    }

    /// Clear active session ID (and the session's own self-spot frequency) from UserDefaults
    func clearActiveSessionId() {
        UserDefaults.standard.removeObject(forKey: activeSessionIdKey)
        clearSelfSpotFrequency()
    }

    /// Check if a frequency change is valid for POTA QSY spotting
    func isValidForQSYSpot(frequency: Double, mode: String) -> Bool {
        let licenseRaw = UserDefaults.standard.string(forKey: "userLicenseClass")
            ?? LicenseClass.extra.rawValue
        let license = LicenseClass(rawValue: licenseRaw) ?? .extra
        let violation = BandPlanService.validate(
            frequencyMHz: frequency, mode: mode, license: license
        )
        return violation == nil || violation?.type == .unusualFrequency
    }

    /// Decrement the rove stop QSO count for a hidden QSO
    func decrementRoveStopQSOCount(for qso: QSO) {
        guard let session = activeSession, session.isRove else {
            return
        }
        let qsoPark = qso.parkReference?.uppercased()
        var stops = session.roveStops
        // Find the matching stop (prefer current open stop, fall back to last matching park)
        if let index = stops.lastIndex(where: {
            $0.parkReference.uppercased() == qsoPark && $0.endedAt == nil
        }) ?? stops.lastIndex(where: {
            $0.parkReference.uppercased() == qsoPark
        }) {
            stops[index].qsoCount = max(0, stops[index].qsoCount - 1)
            session.roveStops = stops
        }
    }

    func writeSessionToWidget(
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

        // Send real-time update to Watch via WatchConnectivity
        let band = session.frequency.map { LoggingSession.bandForFrequency($0) }
        PhoneSessionDelegate.shared.sendSessionUpdate(WatchSessionUpdate(
            qsoCount: session.qsoCount,
            lastCallsign: lastCallsign,
            frequency: freqString,
            band: band,
            mode: session.mode,
            parkReference: session.parkReference,
            activationType: session.activationType.rawValue,
            isPaused: false,
            startedAt: session.startedAt,
            myCallsign: session.myCallsign,
            currentStopPark: session.isRove ? session.roveStops.last?.parkReference : nil,
            stopNumber: session.isRove ? session.roveStops.count : nil,
            totalStops: session.isRove ? session.roveStops.count : nil,
            currentStopQSOs: session.isRove ? session.roveStops.last?.qsoCount : nil
        ))
    }

    /// Detect and report notable activities for a newly logged QSO.
    /// Runs async and never blocks the logger.
    func processActivityForQSO(_ qso: QSO) async {
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

        // Report to server and store server IDs on local items
        let reporter = ActivityReporter()
        await reporter.reportActivities(
            detected, sourceURL: ActivitiesClient.resolvedBaseURL, modelContext: modelContext
        )

        // Notify UI of new activities
        NotificationCenter.default.post(
            name: .didDetectActivities,
            object: nil,
            userInfo: ["count": detected.count]
        )
    }

    func markForUpload(_ qso: QSO) {
        // Skip upload markers for metadata pseudo-modes (WEATHER, SOLAR, NOTE)
        // These are activation metadata from Ham2K PoLo, not actual QSOs
        guard !QSOMode.isMetadata(qso.mode) else {
            return
        }

        // Use cached service configuration (checked at session start)
        if qrzConfigured {
            qso.markNeedsUpload(to: .qrz, context: modelContext)
        }

        // POTA (only if this is a POTA activation, use cached value)
        if activeSession?.isPOTA == true,
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

    /// Report anonymous equipment usage telemetry at session end.
    func reportEquipmentUsage(_ session: LoggingSession) {
        let info = SessionEquipmentInfo(
            radio: session.myRig,
            antenna: session.myAntenna,
            key: session.myKey,
            mic: session.myMic,
            mode: session.mode,
            band: session.band,
            program: session.activationType.rawValue
        )
        let container = modelContext.container
        Task {
            await EquipmentUsageReporter.shared.recordUsage(
                session: info, container: container
            )
        }
    }
}
