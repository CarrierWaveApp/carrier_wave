//
//  SessionLateEntryService.swift
//  CarrierWave
//
//  Log a QSO into a session that has already ended, without reopening it.
//
//  The text line is parsed by the same `QuickEntryParser` the logger uses, the
//  row is persisted through the same shared Rust `SessionApi.logQso` (band from
//  frequency, session-field stamping, RST mode defaults, notes merge), the same
//  upload destinations are marked (`LoggingSessionManager.markForUpload` rules),
//  and the same callsign-lookup enrichment (QRZ / HamDB / cache) fills name,
//  grid, state, country, QTH and licence class. Because the session row already
//  has `status == .completed` and `endedAt` set, `fetch_current_session` never
//  returns it — nothing here disturbs an active activation.
//

import CarrierWaveCore
import CarrierWaveData
import SwiftData
import UIKit

// MARK: - SessionLateEntryService

@MainActor
enum SessionLateEntryService {
    // MARK: Internal

    enum LateEntryError: LocalizedError {
        case storeUnavailable
        case sessionMissing
        case emptyCallsign

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .storeUnavailable:
                "Log store unavailable — QSO was not saved"
            case .sessionMissing:
                "Session not found in the log store"
            case .emptyCallsign:
                "Callsign cannot be empty"
            }
        }
    }

    /// Parse a quick-entry line exactly like the logger's callsign field: a bare
    /// callsign logs with session defaults; anything with spaces goes through
    /// `QuickEntryParser` (multi-callsign first, then single).
    static func parse(_ input: String, rstOrder: RSTOrder) -> [QuickEntryResult] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return []
        }
        guard trimmed.contains(" ") else {
            return [QuickEntryResult(callsign: trimmed.uppercased())]
        }
        if let multi = QuickEntryParser.parseMulti(trimmed, rstOrder: rstOrder), multi.count >= 2 {
            return multi
        }
        if let single = QuickEntryParser.parse(trimmed, rstOrder: rstOrder) {
            return [single]
        }
        return []
    }

    /// Preview tokens for the colour-coded line under the field (same as the logger).
    static func tokens(_ input: String, rstOrder: RSTOrder) -> [ParsedToken] {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(" ") else {
            return []
        }
        if let multi = QuickEntryParser.parseMulti(trimmed, rstOrder: rstOrder), multi.count >= 2 {
            return QuickEntryParser.parseMultiTokens(trimmed, rstOrder: rstOrder)
        }
        return QuickEntryParser.parseTokens(trimmed, rstOrder: rstOrder)
    }

    /// Resolve the QSO timestamp: an explicit Zulu time lands on the session's
    /// UTC day (not today's — the session may be days old); otherwise the
    /// session's end time, which is the latest moment we know the operator was
    /// on the air.
    static func timestamp(for result: QuickEntryResult, session: LoggingSession) -> Date {
        let anchor = session.endedAt ?? Date()
        guard let zulu = result.zuluTime else {
            return anchor
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var comps = calendar.dateComponents([.year, .month, .day], from: anchor)
        comps.hour = zulu.hour
        comps.minute = zulu.minute
        comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: comps) ?? anchor
    }

    /// Log one parsed entry into `session`. `lookup` is the already-resolved
    /// callsign info for this callsign (nil when the lookup hasn't landed yet —
    /// the caller then runs `enrich` after the fact, like the HUNT path).
    @discardableResult
    static func log(
        _ result: QuickEntryResult,
        lookup: CallsignInfo?,
        session: LoggingSession,
        modelContext: ModelContext
    ) throws -> LoggedQSO {
        guard let api = SessionApiRegistry.current,
              let mirror = CwStoreMirrorRegistry.current
        else {
            throw LateEntryError.storeUnavailable
        }
        let input = try makeInput(result, lookup: lookup, session: session)

        let ffiResult: FfiSessionLogResult
        do {
            guard let value = try api.logQso(input: input) else {
                CwStoreWriteLog.shared.record("late entry: session \(input.sessionId) not in cw-store")
                throw LateEntryError.sessionMissing
            }
            ffiResult = value
        } catch let error as LateEntryError {
            throw error
        } catch {
            CwStoreWriteLog.shared.record("late entry logQso threw: \(error)")
            throw LateEntryError.storeUnavailable
        }

        let qso = try FfiReflector.reflect(ffiResult.qso, into: modelContext, mirror: mirror)
        for target in WsjtxFieldService.defaultUploadTargets(for: session) {
            qso.markNeedsUpload(to: target, context: modelContext)
        }
        session.qsoCount = Int(ffiResult.qsoCount)
        try? modelContext.save()

        QSOLedger.append(qso)
        NotificationCenter.default.post(
            name: .didLogQSO, object: nil, userInfo: ["callsign": qso.callsign]
        )
        return LoggedQSO(qso: qso)
    }

    /// Post-log enrichment for a QSO logged before its lookup resolved: the same
    /// fill the logger applies (`fetchAndUpdateQSOMetadata`).
    static func enrich(qsoId: String, callsign: String, modelContext: ModelContext) async {
        let service = CallsignLookupService(modelContext: modelContext)
        guard let info = await service.lookup(CallsignParsing.primaryCallsign(from: callsign)),
              let qso = LogbookIDBridge.fetchQSO(id: qsoId, in: modelContext)
        else {
            return
        }
        qso.name = info.name
        if qso.theirGrid == nil {
            qso.theirGrid = info.grid
        }
        if qso.state == nil {
            qso.state = info.state
        }
        qso.country = info.country
        qso.qth = info.qth
        qso.theirLicenseClass = info.licenseClass
        if info.callsignChangeNote != nil {
            qso.callsignChangeNote =
                "Logged as \(qso.callsign) but operator changed to \(info.callsign)"
        }
        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()
        try? modelContext.save()
    }

    // MARK: Private

    /// Build the Rust log input: logger field precedence (quick entry > lookup),
    /// QRZ callsign redirect, blank RST so the core applies the mode default,
    /// and the resolved timestamp. Upload routing stays Swift (`log`).
    private static func makeInput(
        _ result: QuickEntryResult,
        lookup: CallsignInfo?,
        session: LoggingSession
    ) throws -> FfiSessionLogInput {
        let typed = result.callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !typed.isEmpty else {
            throw LateEntryError.emptyCallsign
        }

        // When QRZ redirected, log the canonical (new) callsign — same as the logger.
        let matched = lookup.flatMap { info in
            info.callsign == CallsignParsing.primaryCallsign(from: typed) ? info : nil
        }
        let callsign = matched?.callsignChangeNote != nil ? matched?.callsign ?? typed : typed
        let changeNote = matched?.callsignChangeNote != nil
            ? "Logged as \(typed) but operator changed to \(matched?.callsign ?? typed)" : nil

        return FfiSessionLogInput(
            // cw-store ids are lowercase; `uuidString` would miss the row.
            sessionId: SwiftDataStoreImporter.uuid(session.id),
            callsign: callsign,
            // Blank RST lets the Rust core apply the mode default (599 / 59).
            rstSent: result.rstSent ?? "",
            rstReceived: result.rstReceived ?? "",
            theirGrid: result.theirGrid.nonEmpty ?? matched?.grid,
            theirPark: result.theirPark.nonEmpty,
            notes: result.notes.nonEmpty,
            name: matched?.name,
            qth: matched?.qth,
            state: result.state.nonEmpty ?? matched?.state,
            country: matched?.country,
            theirLicenseClass: matched?.licenseClass,
            aoaCode: nil,
            callsignChangeNote: changeNote,
            frequencyOverrideMhz: result.frequency,
            modeOverride: result.mode,
            timestampOverride: Int64(timestamp(for: result, session: session).timeIntervalSince1970),
            // Upload routing + presence rows stay Swift (`log`).
            uploadQrz: false,
            uploadPota: false,
            uploadLofi: false,
            uploadClublog: false
        )
    }
}
