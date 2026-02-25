import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - SyncService Club Log Upload Methods

extension SyncService {
    /// Upload to Club Log if configured
    func uploadClubLogIfConfigured(
        qsosNeedingUpload: [QSO]?, timeout: TimeInterval
    ) async -> Result<Int, Error>? {
        guard clublogClient.isConfigured else {
            return nil
        }

        let clublogQSOs = qsosNeedingUpload?
            .filter { $0.needsUpload(to: .clublog) } ?? []
        guard !clublogQSOs.isEmpty else {
            return nil
        }

        let (validQSOs, invalidQSOs) = partitionQSOsByValidity(clublogQSOs)
        await logQSOsWithMissingFields(invalidQSOs, service: .clublog)

        guard !validQSOs.isEmpty else {
            return nil
        }

        await logPendingQSOs(validQSOs, service: .clublog)
        let (_, result) = await uploadClubLogBatch(qsos: validQSOs, timeout: timeout)
        return result
    }

    func uploadClubLogBatch(qsos: [QSO], timeout: TimeInterval) async -> (
        ServiceType, Result<Int, Error>
    ) {
        await MainActor.run {
            self.syncPhase = .uploading(service: .clublog)
            self.serviceSyncStates[.clublog] = .uploading
        }
        do {
            let result = try await withTimeout(seconds: timeout, service: .clublog) {
                try await self.uploadToClubLog(qsos: qsos)
            }
            let downloadedCount = serviceSyncStates[.clublog]?.downloadedCount ?? 0
            await MainActor.run {
                self.serviceSyncStates[.clublog] = .complete(
                    downloaded: downloadedCount, uploaded: result.uploaded
                )
            }
            return (.clublog, .success(result.uploaded))
        } catch {
            await MainActor.run {
                self.serviceSyncStates[.clublog] = .error(error.localizedDescription)
            }
            return (.clublog, .failure(error))
        }
    }

    func uploadToClubLog(qsos: [QSO]) async throws -> ClubLogUploadResult {
        let uploadResult = try await clublogClient.uploadQSOs(qsos)

        // Mark uploaded QSOs
        let accountCallsign = clublogClient.getCallsign()?.uppercased()
        await MainActor.run {
            for qso in qsos {
                let qsoCallsign = qso.myCallsign.uppercased()
                let matches = qsoCallsign.isEmpty || qsoCallsign == accountCallsign
                if matches, let presence = qso.presence(for: .clublog) {
                    presence.needsUpload = false
                    presence.isPresent = true
                    presence.lastConfirmedAt = Date()
                }
            }
        }

        await MainActor.run {
            SyncDebugLog.shared.info(
                "Club Log upload complete: \(uploadResult.uploaded) uploaded, "
                    + "\(uploadResult.skipped) skipped",
                service: .clublog
            )
        }

        return uploadResult
    }
}
