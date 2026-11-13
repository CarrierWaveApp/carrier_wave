import CarrierWaveCore
import CarrierWaveData
import SwiftData
import UIKit

// MARK: - Rust delegation: session lifecycle verbs (C2 remainder)

/// `.on`-mode lifecycle delegation: pause/resume/end/finish/merge/delete run
/// through the shared Rust `SessionApi` (identical to Android), then the
/// returned rows are reflected into the SwiftData replica mirror-suppressed.
/// Every helper returns `false` (or falls back) on ANY failure so the caller
/// runs the existing Swift path — a delegation failure must never lose a
/// session mutation. `reopenSession` needs no verb of its own: its local
/// `endedAt = nil` mutation rides the resume delegation's pre-flush.
extension LoggingSessionManager {
    // MARK: Internal

    /// Delegate a pause: flush the session's local pre-mutations (spot comments,
    /// track points, rove-stop close) through the seam, let Rust flip the status,
    /// reflect the result. The caller skips `session.pause()` + commit on success.
    func pauseSessionViaRust(_ session: LoggingSession) -> Bool {
        transitionViaRust(session, verb: "pause") { api, id in
            try api.pauseSession(id: id)
        }
    }

    /// Delegate a resume. Rust also pauses whatever other session was active in
    /// cw-store, mirroring `resumeSession(_:)`'s rule (the local teardown of that
    /// session has already run via `pauseSession()`).
    func resumeSessionViaRust(_ session: LoggingSession) -> Bool {
        transitionViaRust(session, verb: "resume") { api, id in
            try api.resumeSession(id: id)
        }
    }

    /// Delegate a non-active finish (`finishSession`'s paused branch): end only —
    /// no split, no WPM. Preserves the active/paused end asymmetry.
    func finishPausedSessionViaRust(_ session: LoggingSession) -> Bool {
        transitionViaRust(session, verb: "finish") { api, id in
            try api.endSession(id: id)
        }
    }

    /// Delegate the `endSession` persistence core: end → POTA midnight split →
    /// average-WPM metadata, all written to cw-store by Rust, then reflect every
    /// touched row and re-point the SwiftData QSOs/recordings of split clones.
    /// The caller skips `session.end()` + `splitPOTAAtUTCMidnight` +
    /// `saveAverageWPM` + `commitSessionSplit` on success.
    func endSessionCoreViaRust(_ session: LoggingSession, comments: [POTASpotComment]) -> Bool {
        guard let api = sessionApi, let mirror = rustLogMirror else {
            return false
        }
        let id = SwiftDataStoreImporter.uuid(session.id)
        do {
            try EntityWriteSink.commitUpsert(session, in: modelContext)
            guard let ended = try api.endSession(id: id) else {
                CwStoreWriteLog.shared.record("session end: \(id) not in cw-store")
                return false
            }
            var rows = [ended]
            if session.isPOTA {
                let split = try api.splitAtUtcMidnight(sessionId: id)
                if !split.isEmpty {
                    rows = split
                }
            }
            let wpmValues = comments.compactMap(\.wpm).map(Int32.init)
            let metadata = wpmValues.isEmpty
                ? nil
                : try api.saveAverageWpm(sessionId: id, wpmValues: wpmValues)
            var reflected: [LoggingSession] = []
            for row in rows {
                try reflected.append(FfiReflector.reflect(row, into: modelContext, mirror: mirror))
            }
            if let metadata {
                _ = try FfiReflector.reflect(metadata, into: modelContext, mirror: mirror)
            }
            if reflected.count > 1 {
                try reconcileAfterSplit(original: session, splitSessions: reflected)
            }
            return true
        } catch {
            CwStoreWriteLog.shared.record("session end delegation failed: \(error)")
            return false
        }
    }

    /// Delegate a session delete: Rust hides the QSOs (dropping pending-upload
    /// markers) and deletes the session row in cw-store; the SessionSpot removals
    /// still ride a spot-only seam batch (the Rust verb does not touch spots),
    /// whose suppressed save also flushes the caller's SwiftData mutations.
    /// Falls back to the full seam-batch delete on any failure.
    func commitSessionDeleteViaRustOrSeam(
        session: LoggingSession, spots: [SessionSpot], hiddenQSOs: [QSO]
    ) {
        if let api = sessionApi, rustLogMirror != nil {
            do {
                let deleted = try api.deleteSession(id: SwiftDataStoreImporter.uuid(session.id))
                if deleted, var batch = SeamWriteBatch.make() {
                    for spot in spots {
                        batch.delete(spot)
                    }
                    try batch.commit(in: modelContext)
                    return
                }
                CwStoreWriteLog.shared.record(
                    "session delete: \(session.id) not in cw-store — seam fallback"
                )
            } catch {
                CwStoreWriteLog.shared.record("session delete delegation failed: \(error)")
            }
        }
        commitSessionDelete(session: session, spots: spots, hiddenQSOs: hiddenQSOs)
    }

    /// Delegate a merge (`mergeSessions`): Rust reassigns QSOs/spots/recordings,
    /// expands the target bounds, folds counts, concats photo filenames, and
    /// deletes the source — all in cw-store. On success the caller applies the
    /// identical SwiftData mutations and flushes them suppressed; on failure it
    /// routes the seam batch as before.
    func mergeSessionsViaRust(sourceId: UUID, targetId: UUID) -> Bool {
        guard let api = sessionApi, rustLogMirror != nil else {
            return false
        }
        do {
            return try api.mergeSessions(
                sourceId: SwiftDataStoreImporter.uuid(sourceId),
                targetId: SwiftDataStoreImporter.uuid(targetId)
            )
        } catch {
            CwStoreWriteLog.shared.record("session merge delegation failed: \(error)")
            return false
        }
    }

    /// One mirror-suppressed save — flushes SwiftData mutations whose cw-store
    /// writes Rust already made (merge, split re-pointing) without re-projecting.
    func flushSuppressed() throws {
        guard let mirror = rustLogMirror else {
            try modelContext.save()
            return
        }
        mirror.beginSeamWrite(for: modelContext)
        defer { mirror.endSeamWrite(for: modelContext) }
        try modelContext.save()
    }

    // MARK: Private

    /// Shared single-row transition: pre-flush local session mutations through
    /// the seam (so Rust reads them), run the Rust verb, reflect the returned row
    /// mirror-suppressed. In-place reflection keeps the held `activeSession`
    /// reference and its SwiftUI observation alive.
    private func transitionViaRust(
        _ session: LoggingSession,
        verb: String,
        _ call: (SessionApi, String) throws -> FfiLoggingSession?
    ) -> Bool {
        guard let api = sessionApi, let mirror = rustLogMirror else {
            return false
        }
        let id = SwiftDataStoreImporter.uuid(session.id)
        do {
            try EntityWriteSink.commitUpsert(session, in: modelContext)
            guard let row = try call(api, id) else {
                CwStoreWriteLog.shared.record("session \(verb): \(id) not in cw-store")
                return false
            }
            _ = try FfiReflector.reflect(row, into: modelContext, mirror: mirror)
            return true
        } catch {
            CwStoreWriteLog.shared.record("session \(verb) delegation failed: \(error)")
            return false
        }
    }

    /// After a delegated POTA midnight split: re-embed each rove session's
    /// transitional blob from the structured `rove_stop` table (the split wrote
    /// the table only — clones come back with a nil blob and the original with
    /// the unclipped one), re-point the SwiftData QSOs and WebSDR recordings at
    /// the clone covering their UTC day (the same grouping
    /// `split_at_utc_midnight` used), then push the corrected session rows back
    /// through the sink — its suppressed save also flushes the re-pointed rows,
    /// whose cw-store reassignment Rust already did.
    private func reconcileAfterSplit(
        original: LoggingSession, splitSessions: [LoggingSession]
    ) throws {
        if original.isRove, let store = SeamWriteBatchRegistry.current?.store {
            for session in splitSessions {
                let rows = try store.fetchRoveStops(
                    loggingSessionId: SwiftDataStoreImporter.uuid(session.id)
                )
                session.roveStops = FfiReflector.hydrateRoveStops(rows)
            }
        }
        try repointEntitiesAfterSplit(original: original, splitSessions: splitSessions)
        try EntityWriteSink.commitUpsert(splitSessions, in: modelContext)
    }

    /// Re-point this session's SwiftData QSOs and WebSDR recordings at the split
    /// clone covering their UTC day (mutation only — `reconcileAfterSplit` owns
    /// the flush).
    private func repointEntitiesAfterSplit(
        original: LoggingSession, splitSessions: [LoggingSession]
    ) throws {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        var sessionByDay: [Date: UUID] = [:]
        for session in splitSessions {
            sessionByDay[utcCalendar.startOfDay(for: session.startedAt)] = session.id
        }
        let originalId = original.id
        let qsoDescriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { $0.loggingSessionId == originalId },
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        for qso in (try? modelContext.boundedFetch(qsoDescriptor)) ?? [] {
            let day = utcCalendar.startOfDay(for: qso.timestamp)
            if let target = sessionByDay[day], target != qso.loggingSessionId {
                qso.loggingSessionId = target
            }
        }
        let recPredicate = #Predicate<WebSDRRecording> { $0.loggingSessionId == originalId }
        let recordings = (try? modelContext.fetch(FetchDescriptor(predicate: recPredicate))) ?? []
        for recording in recordings {
            let day = utcCalendar.startOfDay(for: recording.startedAt)
            if let target = sessionByDay[day], target != recording.loggingSessionId {
                recording.loggingSessionId = target
            }
        }
    }
}
