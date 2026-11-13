//
//  WsjtxIngestService+Ingest.swift
//  CarrierWaveData
//
//  The message → log path for `WsjtxIngestService` (CAR-282): route decoded
//  WSJT-X messages, map `QSOLogged` / `LoggedADIF` through the Rust importer,
//  dedup against the store, insert, commit.
//

import CarrierWaveCore
import Foundation
import SwiftData

public extension WsjtxIngestService {
    // MARK: - Message routing

    /// Route one decoded WSJT-X message. Public for tests; the delegate bridge
    /// calls this on the main actor.
    func handleMessage(_ message: FfiWsjtxMessage, from sender: String) {
        lastError = nil
        switch message {
        case let .heartbeat(heartbeat):
            lastHeartbeatAt = Date()
            if connectedClientId != heartbeat.id {
                connectedClientId = heartbeat.id
                record(.info, "WSJT-X \"\(heartbeat.id)\" connected from \(sender)")
            }
        case let .status(status):
            lastStatus = WsjtxStatusSummary(
                clientId: status.id,
                dialFrequencyHz: status.dialFrequencyHz,
                mode: status.mode,
                dxCall: status.dxCall,
                deCall: status.deCall,
                transmitting: status.transmitting,
                receivedAt: Date()
            )
        case let .decode(decode):
            guard decode.new else {
                return
            }
            let snr = decode.snr >= 0 ? "+\(decode.snr)" : "\(decode.snr)"
            record(.decode, "\(snr) dB  \(decode.message.trimmingCharacters(in: .whitespaces))")
        case let .qsoLogged(qso):
            mapAndIngest("QSO for \(qso.dxCall)") {
                try [wsjtxMapQsoLogged(message: qso, context: makeImportContext())]
            }
        case let .loggedAdif(adif):
            mapAndIngest("logged ADIF") {
                try wsjtxMapLoggedAdif(message: adif, context: makeImportContext())
            }
        case let .close(id):
            record(.info, "WSJT-X \"\(id)\" closed")
            lastStatus = nil
            connectedClientId = nil
        case .other:
            break
        }
    }

    /// The import context handed to the Rust mapper for one broadcast.
    func makeImportContext() -> FfiWsjtxImportContext {
        let session = modelContext.flatMap { resolveSession(in: $0) }
        return FfiWsjtxImportContext(
            stationCallsign: stationCallsignProvider(),
            importedAt: Int64(Date().timeIntervalSince1970),
            loggingSessionId: session.map { $0.id.uuidString.lowercased() }
        )
    }

    // MARK: - Insert with dedup

    /// Offer mapped QSOs to the log, one dedup decision each. Public so the
    /// tests (and any future replay tool) can drive it without a socket.
    @discardableResult
    func ingest(_ ffiQsos: [FfiQso]) -> [WsjtxIngestOutcome] {
        guard let context = modelContext else {
            let message = "WSJT-X listener is not attached to a log"
            lastError = message
            record(.error, message)
            return ffiQsos.map { _ in .failed(message) }
        }
        var outcomes: [WsjtxIngestOutcome] = []
        var inserted: [QSO] = []
        for ffi in ffiQsos {
            let (outcome, qso) = stage(ffi, in: context)
            outcomes.append(outcome)
            if let qso {
                inserted.append(qso)
            }
        }
        guard !inserted.isEmpty else {
            return outcomes
        }
        do {
            try commit(inserted, context)
        } catch {
            context.rollback()
            let message = "Could not save: \(Self.describe(error))"
            lastError = message
            record(.error, message)
            let failedIds = Set(inserted.map(\.id))
            return outcomes.map { outcome in
                if case let .inserted(id) = outcome, failedIds.contains(id) {
                    return .failed(message)
                }
                return outcome
            }
        }
        for qso in inserted {
            loggedCount += 1
            let summary = Self.summary(of: qso)
            lastLoggedSummary = summary
            lastLoggedAt = Date()
            record(.qsoLogged, "Logged \(summary)")
            onQSOLogged?(qso)
        }
        return outcomes
    }

    /// Existing row that makes `candidate` a duplicate: same id, or same
    /// `deduplicationKey` among rows for the same callsign within ±3 minutes.
    /// Works on the FFI value so no throwaway `@Model` is created for a dupe.
    static func existingDuplicate(of candidate: FfiQso, in context: ModelContext) throws -> QSO? {
        if let id = UUID(uuidString: candidate.id) {
            var byId = FetchDescriptor<QSO>(predicate: #Predicate<QSO> { $0.id == id })
            byId.fetchLimit = 1
            if let hit = try context.fetch(byId).first {
                return hit
            }
        }

        let callsign = candidate.callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let timestamp = Date(timeIntervalSince1970: TimeInterval(candidate.qsoDate))
        let lower = timestamp.addingTimeInterval(-180)
        let upper = timestamp.addingTimeInterval(180)
        var nearby = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.callsign == callsign && qso.timestamp >= lower && qso.timestamp <= upper
            }
        )
        nearby.fetchLimit = 50
        let key = QSO.makeDeduplicationKey(
            callsign: callsign, band: candidate.band ?? "", mode: candidate.mode ?? "", timestamp: timestamp
        )
        return try context.fetch(nearby).first { $0.deduplicationKey == key }
    }
}

// MARK: - Internals

extension WsjtxIngestService {
    /// Dedup-check one mapped candidate and, if new, hydrate and insert it
    /// (unsaved) into `context`. Returns the QSO only when it was inserted.
    func stage(_ ffi: FfiQso, in context: ModelContext) -> (WsjtxIngestOutcome, QSO?) {
        do {
            if let existing = try Self.existingDuplicate(of: ffi, in: context) {
                duplicateCount += 1
                record(.duplicate, "Already logged: \(Self.summary(of: ffi))")
                return (.duplicate(existing.id), nil)
            }
        } catch {
            let message = "Duplicate check failed: \(Self.describe(error))"
            lastError = message
            record(.error, message)
            return (.failed(message), nil)
        }
        let candidate = FfiReflector.hydrate(ffi)
        let session = resolveSession(in: context)
        if let session {
            candidate.loggingSessionId = session.id
            candidate.cloudDirtyFlag = true
            candidate.modifiedAt = Date()
        }
        context.insert(candidate)
        session?.incrementQSOCount()
        return (.inserted(candidate.id), candidate)
    }

    func resolveSession(in context: ModelContext) -> LoggingSession? {
        if let sessionProvider {
            return sessionProvider(context)
        }
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { $0.statusRawValue == "active" },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Run the Rust mapper and ingest its output, recording a typed error
    /// (`WsjtxError`) as a feed line instead of throwing.
    func mapAndIngest(_ what: String, _ map: () throws -> [FfiQso]) {
        do {
            try ingest(map())
        } catch {
            let text = "Could not read \(what): \(Self.describe(error))"
            lastError = text
            record(.error, text)
        }
    }

    static func summary(of qso: QSO) -> String {
        summary(callsign: qso.callsign, band: qso.band, mode: qso.mode)
    }

    static func summary(of ffi: FfiQso) -> String {
        summary(callsign: ffi.callsign, band: ffi.band ?? "", mode: ffi.mode ?? "")
    }

    private static func summary(callsign: String, band: String, mode: String) -> String {
        var parts = [callsign]
        let bandMode = [band, mode].filter { !$0.isEmpty }.joined(separator: " ")
        if !bandMode.isEmpty {
            parts.append(bandMode)
        }
        return parts.joined(separator: " · ")
    }
}
