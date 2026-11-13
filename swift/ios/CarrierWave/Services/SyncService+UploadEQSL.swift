import CarrierWaveData
import Foundation
import SwiftData

// MARK: - SyncService eQSL Upload Methods

extension SyncService {
    /// Upload to eQSL if configured
    func uploadEQSLIfConfigured(
        qsosNeedingUpload: [QSO]?, timeout: TimeInterval
    ) async -> Result<Int, Error>? {
        guard isUploadEnabled(for: .eqsl) else {
            return nil
        }
        guard eqslClient.isConfigured else {
            await MainActor.run {
                SyncDebugLog.shared.debug(
                    "eQSL upload skipped: not configured",
                    service: .eqsl
                )
            }
            return nil
        }

        let eqslQSOs = qsosNeedingUpload?
            .filter { $0.needsUpload(to: .eqsl) } ?? []
        guard !eqslQSOs.isEmpty else {
            return nil
        }

        let (validQSOs, invalidQSOs) = partitionQSOsByValidity(eqslQSOs)
        await logQSOsWithMissingFields(invalidQSOs, service: .eqsl)

        guard !validQSOs.isEmpty else {
            return nil
        }

        await logPendingQSOs(validQSOs, service: .eqsl)
        let (_, result) = await uploadEQSLBatch(
            qsos: validQSOs, timeout: timeout
        )
        return result
    }

    func uploadEQSLBatch(
        qsos: [QSO], timeout: TimeInterval
    ) async -> (ServiceType, Result<Int, Error>) {
        await MainActor.run {
            self.syncPhase = .uploading(service: .eqsl)
            self.serviceSyncStates[.eqsl] = .uploading
        }
        do {
            let result = try await withTimeout(
                seconds: timeout, service: .eqsl
            ) {
                try await self.uploadToEQSL(qsos: qsos)
            }
            let downloadedCount =
                serviceSyncStates[.eqsl]?.downloadedCount ?? 0
            await MainActor.run {
                self.serviceSyncStates[.eqsl] = .complete(
                    downloaded: downloadedCount,
                    uploaded: result.uploaded
                )
            }
            return (.eqsl, .success(result.uploaded))
        } catch {
            await MainActor.run {
                self.serviceSyncStates[.eqsl] = .error(
                    error.localizedDescription
                )
            }
            return (.eqsl, .failure(error))
        }
    }

    func uploadToEQSL(qsos: [QSO]) async throws -> EQSLUploadResult {
        // Filter out metadata pseudo-modes
        let realQSOs = qsos.filter {
            !QSOMode.isMetadata($0.mode)
        }

        let uploadResult = try await eqslClient.uploadQSOs(realQSOs)

        // Mark uploaded QSOs
        await MainActor.run {
            for qso in realQSOs {
                if let presence = qso.presence(for: .eqsl) {
                    presence.needsUpload = false
                    presence.isPresent = true
                    presence.lastConfirmedAt = Date()
                }
            }
        }

        await MainActor.run {
            SyncDebugLog.shared.info(
                "eQSL upload complete: \(uploadResult.uploaded) uploaded, "
                    + "\(uploadResult.duplicates) dupes, "
                    + "\(uploadResult.rejected) rejected",
                service: .eqsl
            )
        }

        return uploadResult
    }
}
