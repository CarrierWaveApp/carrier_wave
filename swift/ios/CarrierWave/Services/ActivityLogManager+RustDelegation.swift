import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - Rust delegation (C1)

/// `.on`-mode hunter logging: delegate the portable `logQSO` logic to the shared
/// Rust `ActivityLogApi` (identical to Android), then reflect the persisted record
/// into the SwiftData replica. The upload pipeline (ServicePresence + network) stays
/// Swift — Rust is asked to create no upload rows.
extension ActivityLogManager {
    /// The live mirror handle for reflecting Rust writes back (mirror-suppressed).
    var logMirror: CwStoreMirror? {
        CwStoreMirrorRegistry.current
    }

    // swiftlint:disable function_parameter_count

    /// If cw-store is authoritative, log via the Rust core. Non-nil only on full
    /// success; **any** failure (Rust error, log row missing, reflect error) returns
    /// nil so the caller falls through to the SwiftData path — a delegation failure
    /// must never drop the QSO. Mirrors `logQSO`'s parameter list (which the linter
    /// discounts for its defaults); these are always supplied, so no defaults here.
    func logQSOViaRustIfEnabled(
        callsign: String,
        band: String,
        mode: String,
        frequency: Double?,
        rstSent: String,
        rstReceived: String,
        theirGrid: String?,
        theirPark: String?,
        sotaRef: String?,
        notes: String?,
        name: String?,
        state: String?,
        country: String?
    ) -> LoggedQSO? {
        guard let api = hunterApi, let mirror = logMirror, let log = activeLog else {
            return nil
        }
        let profile = currentProfile
        let input = FfiLogQsoInput(
            // cw-store ids are lowercase (SwiftDataStoreImporter.uuid); `uuidString`
            // is uppercase and would miss the row (Rust matches exactly).
            logId: SwiftDataStoreImporter.uuid(log.id),
            callsign: callsign,
            band: band,
            mode: mode,
            frequencyMhz: frequency,
            rstSent: rstSent,
            rstReceived: rstReceived,
            theirGrid: theirGrid,
            theirPark: theirPark,
            sotaRef: sotaRef,
            notes: notes,
            name: name,
            state: state,
            country: country,
            power: profile?.power.map { Int64($0) },
            myRig: profile?.rig,
            stationProfileName: profile?.name,
            // Upload routing stays Swift (`markForUpload` owns the ServicePresence
            // rows + network pipeline), so Rust creates none.
            uploadQrz: false,
            uploadLofi: false,
            uploadClublog: false,
            dailyGoal: Int64(dailyGoal)
        )
        return logQSOViaRust(input, api: api, mirror: mirror)
    }

    // swiftlint:enable function_parameter_count

    /// The Rust `ActivityLogApi` persists the hunter QSO in cw-store (canonical) and
    /// returns it + refreshed today-stats; reflect the QSO into SwiftData, then run
    /// the existing Swift upload marking + side effects.
    private func logQSOViaRust(
        _ input: FfiLogQsoInput,
        api: ActivityLogApi,
        mirror: CwStoreMirror
    ) -> LoggedQSO? {
        let result: FfiLogQsoResult?
        do {
            result = try api.logQso(input: input)
        } catch {
            CwStoreWriteLog.shared.record("hunter logQso threw: \(error)")
            return nil
        }
        guard let result else {
            CwStoreWriteLog.shared.record("hunter logQso: log \(input.logId) not in cw-store")
            return nil
        }
        let qso: QSO
        do {
            qso = try FfiReflector.reflect(result.qso, into: modelContext, mirror: mirror)
        } catch {
            CwStoreWriteLog.shared.record("hunter reflect failed: \(error)")
            return nil
        }
        markForUpload(qso)
        try? modelContext.save()
        QSOLedger.append(qso)
        NotificationCenter.default.post(
            name: .didLogQSO, object: nil, userInfo: ["callsign": qso.callsign]
        )
        todayQSOCount = Int(result.today.qsoCount)
        todayBands = Set(result.today.bands)
        todayModes = Set(result.today.modes)
        dailyGoalReached = result.dailyGoalReached
        detectActivities(for: qso)
        return LoggedQSO(qso: qso)
    }
}
