import CarrierWaveCore
import CarrierWaveData
import SwiftData
import UIKit

// MARK: - SatelliteQuickLogService

/// Post-LOS satellite logging: writes each copied contact through the shared
/// Rust `SessionApi.logQso` under a fresh, **born-completed** satellite
/// session. Because the session is created with `status == .completed` and
/// `endedAt` set, `fetch_current_session` never returns it — an active POTA
/// activation is not paused and no Live Activity / location side effects run.
/// `satName`/`propMode` are forced on every QSO logged here (ADIF SAT_NAME /
/// PROP_MODE=SAT — forgetting prop mode means no LoTW satellite credit).
@MainActor
enum SatelliteQuickLogService {
    // MARK: Internal

    /// One copied contact from the pass.
    struct Contact {
        let callsign: String
        let grid: String?
        let timestamp: Date
    }

    /// The pass being logged: satellite identity + session-level prefills.
    struct PassContext {
        /// Short OSCAR designator ("AO-91") — the LoTW-compatible SAT_NAME.
        let satName: String
        let mode: String
        /// Uplink in MHz — ADIF FREQ/BAND are your transmit side.
        let uplinkMHz: Double?
        let passStart: Date
        let passEnd: Date
        let myGrid: String?
    }

    enum QuickLogError: LocalizedError {
        case storeUnavailable
        case nothingLogged

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .storeUnavailable:
                "Log store unavailable — QSOs were not saved"
            case .nothingLogged:
                "No contacts could be logged"
            }
        }
    }

    /// Log all contacts; returns how many were persisted. Throws without
    /// persisting anything when the Rust store seam is unavailable.
    static func log(
        contacts: [Contact],
        pass: PassContext,
        modelContext: ModelContext
    ) throws -> Int {
        guard let api = SessionApiRegistry.current,
              let mirror = CwStoreMirrorRegistry.current
        else {
            throw QuickLogError.storeUnavailable
        }

        let session = try makeCompletedSession(pass: pass, modelContext: modelContext)
        let env = Environment(
            api: api, mirror: mirror,
            uploads: UploadTargets.current(),
            modelContext: modelContext
        )

        var logged = 0
        var lastCount: Int64 = 0
        for contact in contacts {
            guard let result = logOne(contact, pass: pass, session: session, env: env) else {
                continue
            }
            logged += 1
            lastCount = result
        }
        guard logged > 0 else {
            modelContext.delete(session)
            try? modelContext.save()
            throw QuickLogError.nothingLogged
        }

        session.qsoCount = Int(lastCount)
        try? modelContext.save()
        NotificationCenter.default.post(name: .didLogQSO, object: nil)
        return logged
    }

    // MARK: Private

    /// The resolved write seam for one save: Rust API + mirror + upload
    /// targets + the SwiftData context to reflect into.
    private struct Environment {
        let api: SessionApi
        let mirror: CwStoreMirror
        let uploads: UploadTargets
        let modelContext: ModelContext
    }

    /// Which upload services are configured, resolved once per save (mirrors
    /// `LoggingSessionManager.cacheServiceConfiguration`). POTA is never a
    /// target here — a satellite quick-log session has no park.
    private struct UploadTargets {
        let qrz: Bool
        let lofi: Bool
        let clublog: Bool

        static func current() -> UploadTargets {
            let configured = CarrierWaveData.ServiceConfiguration.configuredUploadServices()
            let clublog =
                (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.clublogEmail)) != nil
                    && (try? KeychainHelper.shared.readString(
                        for: KeychainHelper.Keys.clublogPassword
                    )) != nil
                    && (try? KeychainHelper.shared.readString(
                        for: KeychainHelper.Keys.clublogCallsign
                    )) != nil
            return UploadTargets(
                qrz: configured.contains(.qrz),
                lofi: UserDefaults.standard.bool(forKey: "lofi.deviceLinked"),
                clublog: clublog
            )
        }
    }

    /// Create the pass session already completed and project it into cw-store
    /// so `SessionApi.logQso` can resolve the row.
    private static func makeCompletedSession(
        pass: PassContext,
        modelContext: ModelContext
    ) throws -> LoggingSession {
        let myCallsign = CallsignAliasService.shared.getCurrentCallsign()
            ?? UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        let session = LoggingSession(
            myCallsign: myCallsign,
            startedAt: pass.passStart,
            frequency: pass.uplinkMHz,
            mode: pass.mode,
            myGrid: pass.myGrid
        )
        session.customTitle = "\(pass.satName) pass"
        session.endedAt = pass.passEnd
        session.status = .completed
        session.cloudDirtyFlag = true
        modelContext.insert(session)
        do {
            try EntityWriteSink.commitUpsert(session, in: modelContext)
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("satellite quick-log session upsert failed: \(error)")
            throw QuickLogError.storeUnavailable
        }
        return session
    }

    /// Log one contact through the Rust core and reflect it back. Returns the
    /// session's new QSO count, or nil when this row failed (row is skipped,
    /// failure recorded — never silently dropped without a log line).
    private static func logOne(
        _ contact: Contact,
        pass: PassContext,
        session: LoggingSession,
        env: Environment
    ) -> Int64? {
        let input = FfiSessionLogInput(
            // cw-store ids are lowercase; `uuidString` would miss the row.
            sessionId: SwiftDataStoreImporter.uuid(session.id),
            callsign: contact.callsign,
            rstSent: "",
            rstReceived: "",
            theirGrid: contact.grid,
            theirPark: nil,
            notes: nil,
            name: nil,
            qth: nil,
            state: nil,
            country: nil,
            theirLicenseClass: nil,
            aoaCode: nil,
            callsignChangeNote: nil,
            frequencyOverrideMhz: nil,
            modeOverride: nil,
            timestampOverride: Int64(contact.timestamp.timeIntervalSince1970),
            satName: pass.satName,
            propMode: "SAT",
            // Upload routing + presence rows stay Swift (below).
            uploadQrz: false,
            uploadPota: false,
            uploadLofi: false,
            uploadClublog: false
        )
        do {
            guard let result = try env.api.logQso(input: input) else {
                CwStoreWriteLog.shared.record(
                    "satellite quick-log: session \(input.sessionId) not in cw-store"
                )
                return nil
            }
            let qso = try FfiReflector.reflect(
                result.qso, into: env.modelContext, mirror: env.mirror
            )
            if env.uploads.qrz {
                qso.markNeedsUpload(to: .qrz, context: env.modelContext)
            }
            if env.uploads.lofi {
                qso.markNeedsUpload(to: .lofi, context: env.modelContext)
            }
            if env.uploads.clublog {
                qso.markNeedsUpload(to: .clublog, context: env.modelContext)
            }
            QSOLedger.append(qso)
            return result.qsoCount
        } catch {
            CwStoreWriteLog.shared.record("satellite quick-log row failed: \(error)")
            return nil
        }
    }
}
