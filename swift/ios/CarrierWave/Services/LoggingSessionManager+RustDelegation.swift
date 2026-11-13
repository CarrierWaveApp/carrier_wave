import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - Rust delegation (C2)

/// `.on`-mode session logging: delegate the portable `logQSO` logic to the shared
/// Rust `SessionApi` (band-from-freq / session-field stamping / notes / today count
/// identical to Android), then reflect the persisted record into the SwiftData
/// replica. The upload pipeline (ServicePresence + network), rove-stop bookkeeping,
/// Live Activity, widget, and activity detection stay Swift. Contest sessions ride
/// the same path — `log_qso` stamps the contest fields (2026-07-04 contest port);
/// scoring runs separately in the Rust `ContestEngineApi` via `ContestManager`.
extension LoggingSessionManager {
    /// The shared session API. The logger is all-in on Rust: it delegates
    /// whenever the cw-store seam is built (every mode except the hard `.off`
    /// kill switch / the experiment being disabled, where the registry is nil and
    /// the logger surfaces an error rather than falling back to a Swift QSO path).
    var sessionApi: SessionApi? {
        SessionApiRegistry.current
    }

    /// The live mirror handle for reflecting Rust writes back (mirror-suppressed).
    var rustLogMirror: CwStoreMirror? {
        CwStoreMirrorRegistry.current
    }

    // swiftlint:disable function_parameter_count

    /// If cw-store is authoritative, log via the Rust core. Non-nil only on full
    /// success; **any** failure (Rust error, session row missing, reflect error)
    /// returns nil so the caller falls through to the SwiftData path — a delegation
    /// failure must never drop the QSO. `notes` is the raw user note — the Rust core
    /// prepends the session `qsoComment` itself, so the Swift `combineNotes` (which
    /// also prepends it) is not used here. For contest sessions the contest fields
    /// are stamped from the session + per-QSO exchange values (the `isContest`
    /// branch of the SwiftData path).
    func logQSOViaRustIfEnabled(
        callsign: String,
        rstSent: String,
        rstReceived: String,
        theirGrid: String?,
        theirParkReference: String?,
        notes: String?,
        name: String?,
        qth: String?,
        state: String?,
        country: String?,
        theirLicenseClass: String?,
        aoaCode: String?,
        callsignChangeNote: String?,
        contestExchangeSent: String?,
        contestExchangeReceived: String?,
        contestSerialSent: Int?,
        contestSerialReceived: Int?,
        frequencyOverride: Double?,
        modeOverride: String?,
        timestampOverride: Date?
    ) -> LoggedQSO? {
        guard let api = sessionApi, let mirror = rustLogMirror,
              let session = activeSession
        else {
            return nil
        }
        let isContest = session.isContest
        let input = FfiSessionLogInput(
            // cw-store ids are lowercase (SwiftDataStoreImporter.uuid); `uuidString`
            // is uppercase and would miss the row (Rust matches exactly).
            sessionId: SwiftDataStoreImporter.uuid(session.id),
            callsign: callsign,
            rstSent: rstSent,
            rstReceived: rstReceived,
            theirGrid: theirGrid,
            theirPark: theirParkReference,
            notes: notes,
            name: name,
            qth: qth,
            state: state,
            country: country,
            theirLicenseClass: theirLicenseClass,
            aoaCode: aoaCode,
            callsignChangeNote: callsignChangeNote,
            frequencyOverrideMhz: frequencyOverride,
            modeOverride: modeOverride,
            timestampOverride: timestampOverride.map { Int64($0.timeIntervalSince1970) },
            contestName: isContest ? session.contestId : nil,
            contestSerialSent: isContest ? contestSerialSent.map(Int64.init) : nil,
            contestSerialReceived: isContest ? contestSerialReceived.map(Int64.init) : nil,
            contestExchangeSent: isContest ? contestExchangeSent : nil,
            contestExchangeReceived: isContest ? contestExchangeReceived : nil,
            // Upload routing + presence rows stay Swift (`markForUpload`).
            uploadQrz: false,
            uploadPota: false,
            uploadLofi: false,
            uploadClublog: false
        )
        return logQSOViaRust(input, api: api, mirror: mirror, session: session)
    }

    // swiftlint:enable function_parameter_count

    /// Apply a Rust command-handler `SessionUpdated` outcome: reflect the
    /// cw-store-mutated session into SwiftData and run the native side effects
    /// (Live Activity, radio mode/frequency, WebSDR retune, first-frequency
    /// auto-spot) that can't live in Rust. Returns `false` when the mirror is
    /// unavailable so the caller falls back to the native command path.
    @discardableResult
    func applyCommandSessionUpdate(
        _ ffi: FfiLoggingSession, tunedFrequency: Double?, autoSpotFirstSet: Bool
    ) -> Bool {
        guard let mirror = rustLogMirror else {
            return false
        }
        do {
            let session = try FfiReflector.reflect(ffi, into: modelContext, mirror: mirror)
            activeSession = session
            updateLiveActivity()
            sendModeToRadio(session.mode)
            if let freq = tunedFrequency {
                // FREQ command is an explicit own QSY — it moves the self-spot
                // frequency (CAR-296), unlike a hunt tune.
                recordSelfSpotFrequency(freq, for: session.id)
                sendFrequencyToRadio(freq)
                if webSDRSession.state == .recording {
                    Task { await webSDRSession.retune(frequencyMHz: freq) }
                }
            }
            if autoSpotFirstSet {
                Task { await postSpot() }
            }
            return true
        } catch {
            CwStoreWriteLog.shared.record("command session reflect failed: \(error)")
            return false
        }
    }

    /// The Rust `SessionApi` persists the QSO in cw-store (canonical, incrementing
    /// the session count) and returns it + the new count; reflect the QSO into
    /// SwiftData, mirror the count onto the `@Observable` session, then run the
    /// existing Swift bookkeeping + side effects.
    private func logQSOViaRust(
        _ input: FfiSessionLogInput,
        api: SessionApi,
        mirror: CwStoreMirror,
        session: LoggingSession
    ) -> LoggedQSO? {
        let result: FfiSessionLogResult?
        do {
            result = try api.logQso(input: input)
        } catch {
            CwStoreWriteLog.shared.record("session logQso threw: \(error)")
            return nil
        }
        guard let result else {
            CwStoreWriteLog.shared.record("session logQso: session \(input.sessionId) not in cw-store")
            return nil
        }
        let qso: QSO
        do {
            qso = try FfiReflector.reflect(result.qso, into: modelContext, mirror: mirror)
        } catch {
            CwStoreWriteLog.shared.record("session reflect failed: \(error)")
            return nil
        }
        session.qsoCount = Int(result.qsoCount)
        incrementCurrentRoveStopQSOCount()
        markForUpload(qso)
        try? modelContext.save()
        QSOLedger.append(qso)
        NotificationCenter.default.post(
            name: .didLogQSO, object: nil, userInfo: ["callsign": qso.callsign]
        )
        writeSessionToWidget(session, lastCallsign: qso.callsign)
        updateLiveActivity(lastCallsign: qso.callsign)
        Task { [weak self] in
            await self?.processActivityForQSO(qso)
        }
        return LoggedQSO(qso: qso)
    }
}
