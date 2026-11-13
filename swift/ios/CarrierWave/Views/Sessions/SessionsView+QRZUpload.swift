// SessionsView QRZ Upload
//
// QRZ upload actions and helpers for the Sessions list.

import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QRZ Upload

extension SessionsView {
    func computeQRZPendingCounts(qsoMap: [UUID: [QSO]]) {
        let qrzIsConfigured = CarrierWaveData.ServiceConfiguration.isConfigured(.qrz)

        // Backfill: if QRZ is configured, ensure all non-metadata QSOs
        // have a QRZ service presence. QSOs logged before QRZ was configured
        // (or during a session that cached stale credentials) may be missing one.
        var didBackfill = false
        if qrzIsConfigured {
            for (_, qsos) in qsoMap {
                for qso in qsos where !QSOMode.isMetadata(qso.mode) {
                    if qso.presence(for: .qrz) == nil {
                        qso.markNeedsUpload(to: .qrz, context: modelContext)
                        didBackfill = true
                    }
                }
            }
            if didBackfill {
                try? modelContext.save()
            }
        }

        var counts: [UUID: Int] = [:]
        for (sessionId, qsos) in qsoMap {
            let pending = qsos.filter { $0.needsUpload(to: .qrz) }.count
            if pending > 0 {
                counts[sessionId] = pending
            }
        }
        qrzPendingBySessionId = counts
    }

    func performQRZUpload(qsos: [QSO]) async -> String? {
        guard let qrzClient else {
            return "QRZ client not available"
        }

        let pendingQSOs = qsos.filter { $0.needsUpload(to: .qrz) }
        guard !pendingQSOs.isEmpty else {
            return nil
        }

        do {
            let result = try await qrzClient.uploadQSOs(pendingQSOs)
            // Re-fetch confirmed QSOs by PersistentIdentifier for fresh model access
            for persistentID in result.confirmedIDs {
                guard let qso = modelContext.model(for: persistentID) as? QSO else {
                    continue
                }
                if let presence = qso.presence(for: .qrz) {
                    // CAR-244: see SyncService+Upload.swift; gate dirty on
                    // actual state change to avoid heartbeat-only churn.
                    let stateChanged = !presence.isPresent || presence.needsUpload
                    presence.needsUpload = false
                    presence.isPresent = true
                    presence.lastConfirmedAt = Date()
                    if stateChanged {
                        presence.cloudDirtyFlag = true
                    }
                }
                if let logId = result.logIdsByPersistentID[persistentID] {
                    qso.qrzLogId = logId
                }
            }
            try? modelContext.save()
            await loadSessions()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
