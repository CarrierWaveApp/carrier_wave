//
//  LoggingSessionManager+FT8QSOLogger.swift
//  CarrierWave
//

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - LoggingSessionManager + FT8QSOLogger

extension LoggingSessionManager: FT8QSOLogger {
    func logFT8QSO(_ data: FT8CompletedQSOData) -> LoggedQSO? {
        // DXCC + country derive synchronously from the callsign prefix; fall back to
        // the reported grid for stations whose prefix resists matching.
        let entity = LocationPrefixLookup.entity(forCallsign: data.callsign)
            ?? data.theirGrid.flatMap { LocationPrefixLookup.nearest(grid: $0) }

        // LoggingSessionManager derives band/mode/frequency from the active session,
        // so we delegate to the existing logQSO method for those fields.
        guard let logged = logQSO(
            callsign: data.callsign,
            rstSent: data.rstSent,
            rstReceived: data.rstReceived,
            theirGrid: data.theirGrid,
            country: entity?.name
        ) else {
            return nil
        }

        // The DXCC stamp + async enrichment both mutate the live QSO; re-fetch it via
        // the id-bridge (this type stays SwiftData-coupled for persistence).
        if let qso = LogbookIDBridge.fetchQSO(id: logged.id, in: modelContext) {
            if let entityID = entity?.id {
                qso.dxcc = entityID
                qso.cloudDirtyFlag = true
                qso.modifiedAt = Date()
                try? modelContext.save()
            }
            backfillFT8Lookup(for: qso, callsign: data.callsign)
        }

        return logged
    }

    /// Best-effort enrichment after an FT8 QSO is logged: pull state/name/country from
    /// the callsign lookup pipeline (FCC offline → Polo → QRZ → HamDB) and update the
    /// QSO in place. Runs detached so it never blocks the cycle slot boundary.
    private func backfillFT8Lookup(for qso: QSO, callsign: String) {
        let context = modelContext
        Task { @MainActor in
            let service = CallsignLookupService(modelContext: context)
            guard let info = await service.lookup(callsign) else {
                return
            }
            var didChange = false
            if (qso.state ?? "").isEmpty, let state = info.state, !state.isEmpty {
                qso.state = state
                didChange = true
            }
            if (qso.name ?? "").isEmpty, let name = info.name, !name.isEmpty {
                qso.name = name
                didChange = true
            }
            if (qso.country ?? "").isEmpty, let country = info.country, !country.isEmpty {
                qso.country = country
                didChange = true
            }
            if didChange {
                qso.cloudDirtyFlag = true
                qso.modifiedAt = Date()
                try? context.save()
            }
        }
    }
}
