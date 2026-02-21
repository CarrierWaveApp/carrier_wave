import CarrierWaveCore
import Foundation

// MARK: - Shared Helpers

extension LoggingSessionManager {
    /// Save active session ID to UserDefaults
    func saveActiveSessionId(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeSessionIdKey)
    }

    /// Clear active session ID from UserDefaults
    func clearActiveSessionId() {
        UserDefaults.standard.removeObject(forKey: activeSessionIdKey)
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

    /// Combine notes and operator name into a single notes field
    func combineNotes(notes: String?, operatorName: String?) -> String? {
        var parts: [String] = []

        if let op = operatorName, !op.isEmpty {
            parts.append("OP: \(op)")
        }

        if let n = notes, !n.isEmpty {
            parts.append(n)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " | ")
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

    func markForUpload(_ qso: QSO) {
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
