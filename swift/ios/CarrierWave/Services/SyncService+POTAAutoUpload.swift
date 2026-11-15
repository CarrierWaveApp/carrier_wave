import CarrierWaveData
import SwiftData
import UIKit

// MARK: - SyncService Automatic POTA Upload

extension SyncService {
    /// What an automatic POTA upload pass did.
    enum POTAAutoUploadOutcome {
        /// Nothing was sent: uploads off, nothing settled, or pacing held it back.
        case idle
        case uploaded(Int)
        case failure(Error)
    }

    /// Upload settled POTA activations as part of a sync. Each activation goes up
    /// once it is finished (`POTAAutoUploadPolicy`), and passes are paced so a
    /// failing upload is not retried on every sync tick.
    func autoUploadToPOTA(candidates: [QSO]) async -> POTAAutoUploadOutcome {
        guard isUploadEnabled(for: .pota), potaAuthService.isConfigured else {
            return .idle
        }
        let pending = candidates.filter {
            $0.needsUpload(to: .pota) && !QSOMode.isMetadata($0.mode)
        }
        let ready = settledPOTAQSOs(pending)
        guard !ready.isEmpty else {
            return .idle
        }

        let throttle = POTAAutoUploadThrottle()
        let wait = throttle.secondsUntilNextAttempt()
        guard wait <= 0 else {
            SyncDebugLog.shared.info(
                "POTA upload paced: \(ready.count) QSO(s) wait \(Int(wait / 60) + 1) more min "
                    + "(\(throttle.consecutiveFailures) failed pass(es) in a row)",
                service: .pota
            )
            return .idle
        }

        syncPhase = .uploading(service: .pota)
        serviceSyncStates[.pota] = .uploading
        do {
            let result = try await withTimeout(
                seconds: extendedSyncTimeoutSeconds, service: .pota
            ) {
                await self.uploadToPOTA(qsos: ready)
            }
            throttle.recordAttempt(failed: result.failed > 0)
            if modelContext.hasChanges {
                try modelContext.save()
            }
            return .uploaded(result.uploaded)
        } catch {
            throttle.recordAttempt(failed: true)
            SyncDebugLog.shared.error(
                "POTA upload failed: \(error.localizedDescription)", service: .pota
            )
            return .failure(error)
        }
    }

    /// Keep only QSOs whose activation (park + UTC day) has settled, logging
    /// what was left behind and why.
    func settledPOTAQSOs(_ pending: [QSO], now: Date = Date()) -> [QSO] {
        let activeSessionId = UserDefaults.standard
            .string(forKey: "activeLoggingSessionId")
            .flatMap(UUID.init(uuidString:))

        var ready: [PersistentIdentifier: QSO] = [:]
        var held: [POTAAutoUploadPolicy.Hold: Int] = [:]
        for (_, group) in groupQSOsByParkAndDate(pending) {
            guard let newest = group.map(\.timestamp).max() else {
                continue
            }
            let inActiveSession = activeSessionId != nil
                && group.contains { $0.loggingSessionId == activeSessionId }
            if let hold = POTAAutoUploadPolicy.hold(
                newestQSO: newest, inActiveSession: inActiveSession, now: now
            ) {
                held[hold, default: 0] += 1
                continue
            }
            for qso in group {
                ready[qso.persistentModelID] = qso
            }
        }

        if !held.isEmpty {
            SyncDebugLog.shared.debug(
                "POTA upload held activations: "
                    + "\(held[.sessionActive] ?? 0) in the active session, "
                    + "\(held[.stillSettling] ?? 0) logged in the last "
                    + "\(Int(POTAAutoUploadPolicy.quietPeriod / 60)) min, "
                    + "\(held[.tooOld] ?? 0) too old (upload manually)",
                service: .pota
            )
        }
        return Array(ready.values)
    }
}
