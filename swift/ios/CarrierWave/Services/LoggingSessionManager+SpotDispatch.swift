// Per-program spot helpers used by the unified `postSpot` dispatcher in
// `LoggingSessionManager+Spotting.swift`. Split out to keep the parent file
// under SwiftLint's 500-line limit.

import CarrierWaveCore
import CarrierWaveData
import Foundation

extension LoggingSessionManager {
    // MARK: - Self-Spot Frequency (CAR-296)

    // `session.frequency` is the frequency the operator is *currently* on — it
    // follows hunt taps so the hunted QSO logs on the right frequency. Self-spots
    // must not read it: while the activator is tuned away working another
    // station, the periodic re-spot would advertise the other operator's
    // frequency. The operator's own running frequency is tracked separately and
    // only moved by non-hunting updates (manual QSY, FREQ command, CAT dial).
    // Persisted in UserDefaults (keyed to the session id) so it survives relaunch.

    /// UserDefaults key for the operator's own (self-spot) frequency in MHz.
    var selfSpotFrequencyKey: String {
        "activeLoggingSessionSelfSpotFrequency"
    }

    /// UserDefaults key for the session id the recorded frequency belongs to.
    var selfSpotFrequencySessionIdKey: String {
        "activeLoggingSessionSelfSpotSessionId"
    }

    /// The frequency self-spots and re-spots advertise for the active session:
    /// the operator's own running frequency, falling back to the session
    /// frequency when none has been recorded yet.
    var selfSpotFrequency: Double? {
        guard let session = activeSession else {
            return nil
        }
        return spotFrequency(for: session)
    }

    /// Resolve the frequency a self-spot for `session` should advertise. Uses
    /// the recorded own frequency when it belongs to `session`; otherwise the
    /// session's current frequency (e.g. sessions ended before a record existed).
    func spotFrequency(for session: LoggingSession) -> Double? {
        recordedSelfSpotFrequency(for: session.id) ?? session.frequency
    }

    /// Record `frequency` as the operator's own running frequency for `sessionId`.
    func recordSelfSpotFrequency(_ frequency: Double, for sessionId: UUID) {
        let defaults = UserDefaults.standard
        defaults.set(frequency, forKey: selfSpotFrequencyKey)
        defaults.set(sessionId.uuidString, forKey: selfSpotFrequencySessionIdKey)
    }

    /// The recorded own frequency, or nil if none is stored for `sessionId`.
    func recordedSelfSpotFrequency(for sessionId: UUID) -> Double? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: selfSpotFrequencySessionIdKey) == sessionId.uuidString,
              let frequency = defaults.object(forKey: selfSpotFrequencyKey) as? Double
        else {
            return nil
        }
        return frequency
    }

    /// Forget the recorded own frequency (session ended, paused, or deleted).
    func clearSelfSpotFrequency() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: selfSpotFrequencyKey)
        defaults.removeObject(forKey: selfSpotFrequencySessionIdKey)
    }

    // MARK: - Dispatch Helpers

    /// Validate that `freq` is inside the amateur bands for `mode`. Logs a
    /// warning and returns false if it isn't. Uses the most permissive license
    /// class so the check only catches band-boundary violations, not privilege
    /// gaps.
    func isFrequencyInBand(_ freq: Double, mode: String) -> Bool {
        let violation = BandPlanService.validate(
            frequencyMHz: freq, mode: mode, license: .extra
        )
        if let violation, violation.type == .outOfBand {
            SyncDebugLog.shared.warning(
                "Skipping spot: frequency \(FrequencyFormatter.format(freq)) is outside amateur bands",
                service: .pota
            )
            return false
        }
        return true
    }

    /// Surface the result of a multi-program spot dispatch as a single toast.
    /// Successful programs are joined into the toast label so the user sees
    /// every reference that was spotted; if everything failed, surface the
    /// first error so the user has something actionable.
    func presentSpotToast(
        posted: [String],
        failures: [String],
        freq: Double,
        comment: String?
    ) {
        if !posted.isEmpty {
            let label = posted.joined(separator: ", ")
            if let comment, !comment.isEmpty {
                // Echo the comment that actually went out — hardcoding "QSY"
                // here made a QRT self-spot read as a QSY in the app while the
                // spot POTA received said QRT (CAR-347).
                ToastManager.shared.spotPosted(
                    park: label, comment: "\(comment) · \(FrequencyFormatter.format(freq))"
                )
            } else {
                ToastManager.shared.spotPosted(park: label)
            }
        } else if let first = failures.first {
            ToastManager.shared.error(first)
        }
    }

    /// Post a POTA self-spot for every park reference in the (possibly n-fer) session.
    /// Returns the label to surface in a success toast (or nil if none succeeded) and
    /// any per-park error messages for the caller to forward to the user.
    func postPOTASpot(
        spotCallsign: String,
        parkRef: String,
        freq: Double,
        mode: String,
        comment: String?
    ) async -> (successLabel: String?, errors: [String]) {
        let parks = ParkReference.split(parkRef)
        let potaClient = POTAClient(authService: potaAuthService ?? POTAAuthService())
        var successCount = 0
        var errors: [String] = []

        for park in parks {
            do {
                _ = try await potaClient.postSpot(
                    callsign: spotCallsign, reference: park,
                    frequency: freq * 1_000, mode: mode, comments: comment
                )
                successCount += 1
                let msg = comment != nil ? "\(comment!) spot posted" : "Auto-spot posted"
                SyncDebugLog.shared.info("\(msg) for \(park)", service: .pota)
            } catch {
                let detail = "POTA \(park): \(error.localizedDescription)"
                errors.append(detail)
                SyncDebugLog.shared.error(
                    "Spot failed for \(park): \(error.localizedDescription)", service: .pota
                )
            }
        }

        guard successCount > 0 else {
            return (nil, errors)
        }
        let label = parks.count > 1 ? "\(parks.count) parks" : parks.first ?? parkRef
        return (label, errors)
    }

    /// Post a SOTA self-spot. SOTAwatch's spots POST is currently public, so
    /// we don't need stored credentials — the spotter callsign is the
    /// operator's callsign for self-spots.
    func postSOTASpot(
        spotCallsign: String,
        summitRef: String,
        freq: Double,
        mode: String,
        comment: String?
    ) async throws {
        let client = SOTAClient()
        try await client.postSpot(
            activatorCallsign: spotCallsign,
            spotterCallsign: spotCallsign,
            summitCode: summitRef,
            frequencyMHz: freq,
            mode: mode,
            comments: comment
        )
        let msg = comment.map { "\"\($0)\" spot posted" } ?? "Auto-spot posted"
        SyncDebugLog.shared.info("SOTA \(msg) for \(summitRef)")
    }
}
