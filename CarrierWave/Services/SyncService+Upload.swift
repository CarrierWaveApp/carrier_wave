import Foundation
import SwiftData

// MARK: - SyncService Upload Methods

extension SyncService {
    func uploadToAllDestinations() async -> (
        results: [ServiceType: Result<Int, Error>], potaMaintenanceSkipped: Bool
    ) {
        let qsosNeedingUpload = try? fetchQSOsNeedingUpload()
        let timeout = syncTimeoutSeconds
        var potaMaintenanceSkipped = false
        var results: [ServiceType: Result<Int, Error>] = [:]

        // Log all QSOs needing upload for debugging
        if let qsos = qsosNeedingUpload, !qsos.isEmpty {
            await MainActor.run {
                SyncDebugLog.shared.debug(
                    "Found \(qsos.count) QSO(s) with pending uploads",
                    service: nil
                )
            }
        }

        // QRZ upload
        if qrzClient.hasApiKey() {
            let qrzQSOs = qsosNeedingUpload?.filter { $0.needsUpload(to: .qrz) } ?? []
            if !qrzQSOs.isEmpty {
                await logPendingQSOs(qrzQSOs, service: .qrz)
                let (service, result) = await uploadQRZBatch(qsos: qrzQSOs, timeout: timeout)
                results[service] = result
            }
        }

        // POTA upload (skip during maintenance window)
        // Use isConfigured to allow upload even if token expired - ensureValidToken will re-auth
        if potaAuthService.isConfigured {
            if POTAClient.isInMaintenanceWindow() {
                potaMaintenanceSkipped = true
            } else {
                let potaQSOs =
                    qsosNeedingUpload?.filter {
                        $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
                    } ?? []
                if !potaQSOs.isEmpty {
                    await logPendingQSOs(potaQSOs, service: .pota)
                    let (service, result) = await uploadPOTABatch(qsos: potaQSOs, timeout: timeout)
                    results[service] = result
                }

                // Log QSOs that need POTA upload but have no park reference
                let potaQSOsNoPark =
                    qsosNeedingUpload?.filter {
                        $0.needsUpload(to: .pota) && ($0.parkReference?.isEmpty ?? true)
                    } ?? []
                await logPOTAQSOsWithoutPark(potaQSOsNoPark)
            }
        }

        return (results: results, potaMaintenanceSkipped: potaMaintenanceSkipped)
    }

    /// Log QSOs that need POTA upload but have no park reference
    private func logPOTAQSOsWithoutPark(_ qsos: [QSO]) async {
        guard !qsos.isEmpty else {
            return
        }
        await MainActor.run {
            SyncDebugLog.shared.warning(
                "\(qsos.count) QSO(s) need POTA upload but have no park reference",
                service: .pota
            )
            for qso in qsos.prefix(10) {
                let dateStr = Self.debugDateFormatter.string(from: qso.timestamp)
                SyncDebugLog.shared.debug(
                    "  - \(qso.callsign) @ \(dateStr) (no park ref)",
                    service: .pota
                )
            }
            if qsos.count > 10 {
                SyncDebugLog.shared.debug(
                    "  ... and \(qsos.count - 10) more",
                    service: .pota
                )
            }
        }
    }

    /// Log details about pending QSOs for debugging
    private func logPendingQSOs(_ qsos: [QSO], service: ServiceType) async {
        await MainActor.run {
            SyncDebugLog.shared.info(
                "Pending \(service.displayName) uploads: \(qsos.count) QSO(s)",
                service: service
            )

            // Log details for each pending QSO (up to 20)
            for qso in qsos.prefix(20) {
                let dateStr = Self.debugDateFormatter.string(from: qso.timestamp)
                let presence = qso.presence(for: service)
                let presenceInfo =
                    presence.map {
                        "isPresent=\($0.isPresent), needsUpload=\($0.needsUpload), rejected=\($0.uploadRejected)"
                    } ?? "no presence record"

                var details = "\(qso.callsign) @ \(dateStr)"
                details += " | band=\(qso.band), mode=\(qso.mode)"
                if let park = qso.parkReference, !park.isEmpty {
                    details += " | park=\(park)"
                }
                details += " | myCall=\(qso.myCallsign)"
                details += " | [\(presenceInfo)]"

                SyncDebugLog.shared.debug("  - \(details)", service: service)
            }

            if qsos.count > 20 {
                SyncDebugLog.shared.debug(
                    "  ... and \(qsos.count - 20) more pending",
                    service: service
                )
            }
        }
    }

    /// Date formatter for debug logging
    private static let debugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Log failed QSOs for debugging (call from MainActor)
    @MainActor
    private func logFailedQSOs(_ qsos: [QSO], reason: String) {
        for qso in qsos.prefix(5) {
            let dateStr = Self.debugDateFormatter.string(from: qso.timestamp)
            SyncDebugLog.shared.debug(
                "  - \(qso.callsign) @ \(dateStr) (\(reason))",
                service: .pota
            )
        }
        if qsos.count > 5 {
            SyncDebugLog.shared.debug(
                "  ... and \(qsos.count - 5) more",
                service: .pota
            )
        }
    }

    private func uploadQRZBatch(qsos: [QSO], timeout: TimeInterval) async -> (
        ServiceType, Result<Int, Error>
    ) {
        await MainActor.run { self.syncPhase = .uploading(service: .qrz) }
        do {
            let result = try await withTimeout(seconds: timeout, service: .qrz) {
                try await self.uploadToQRZ(qsos: qsos)
            }
            return (.qrz, .success(result.uploaded))
        } catch {
            return (.qrz, .failure(error))
        }
    }

    private func uploadPOTABatch(qsos: [QSO], timeout: TimeInterval) async -> (
        ServiceType, Result<Int, Error>
    ) {
        await MainActor.run { self.syncPhase = .uploading(service: .pota) }
        do {
            let count = try await withTimeout(seconds: timeout, service: .pota) {
                try await self.uploadToPOTA(qsos: qsos)
            }
            return (.pota, .success(count))
        } catch {
            return (.pota, .failure(error))
        }
    }

    func fetchQSOsNeedingUpload() throws -> [QSO] {
        // Defense-in-depth: filter to primary callsign even though ImportService
        // should not create upload markers for non-primary callsign QSOs.
        // This catches any legacy data or edge cases.
        let primaryCallsign = CallsignAliasService.shared.getCurrentCallsign()?.uppercased()

        let descriptor = FetchDescriptor<QSO>()
        let allQSOs = try modelContext.fetch(descriptor)
        return allQSOs.filter { qso in
            // Must have at least one service needing upload
            guard qso.servicePresence.contains(where: \.needsUpload) else {
                return false
            }
            // Must match primary callsign (or be empty, or no primary configured)
            let qsoCallsign = qso.myCallsign.uppercased()
            return qsoCallsign.isEmpty || primaryCallsign == nil || qsoCallsign == primaryCallsign
        }
    }

    func uploadToQRZ(qsos: [QSO]) async throws -> (uploaded: Int, skipped: Int) {
        let batchSize = 50
        var totalUploaded = 0
        var totalSkipped = 0

        for batch in stride(from: 0, to: qsos.count, by: batchSize) {
            let end = min(batch + batchSize, qsos.count)
            let batchQSOs = Array(qsos[batch ..< end])

            let uploadResult = try await qrzClient.uploadQSOs(batchQSOs)
            totalUploaded += uploadResult.uploaded
            totalSkipped += uploadResult.skipped

            // Only clear needsUpload for QSOs that were actually uploaded (matching callsign)
            // Non-matching QSOs keep their needsUpload flag - they're just skipped, not rejected
            let accountCallsign = qrzClient.getCallsign()?.uppercased()
            await MainActor.run {
                for qso in batchQSOs {
                    let qsoCallsign = qso.myCallsign.uppercased()
                    let matches = qsoCallsign.isEmpty || qsoCallsign == accountCallsign
                    if matches, let presence = qso.presence(for: .qrz) {
                        presence.needsUpload = false
                    } else {
                        // Log why this QSO wasn't marked as uploaded
                        let dateStr = Self.debugDateFormatter.string(from: qso.timestamp)
                        let acct = accountCallsign ?? "nil"
                        SyncDebugLog.shared.debug(
                            "QRZ skip (callsign mismatch): \(qso.callsign) @ \(dateStr) | "
                                + "myCall=\(qso.myCallsign) vs account=\(acct)",
                            service: .qrz
                        )
                    }
                }
            }
        }

        // Warn user if QSOs were skipped due to callsign mismatch
        if totalSkipped > 0 {
            let callsign = qrzClient.getCallsign() ?? "unknown"
            SyncDebugLog.shared.warning(
                "Skipped \(totalSkipped) QSOs from other callsigns (QRZ account: \(callsign)). "
                    + "Go to Settings > Callsign Aliases to delete non-primary callsign QSOs.",
                service: .qrz
            )
        }

        // Log final state
        await MainActor.run {
            SyncDebugLog.shared.info(
                "QRZ upload complete: \(totalUploaded) uploaded, \(totalSkipped) skipped",
                service: .qrz
            )
        }

        return (uploaded: totalUploaded, skipped: totalSkipped)
    }

    func uploadToPOTA(qsos: [QSO]) async throws -> Int {
        // Filter out metadata pseudo-modes before grouping
        let realQsos = qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
        let byPark = POTAClient.groupQSOsByPark(realQsos)
        var totalUploaded = 0
        var totalFailed = 0

        await logPOTAUploadStart(qsos: qsos, realQsos: realQsos, parkCount: byPark.count)

        for (parkRef, parkQSOs) in byPark {
            let result = await uploadParkToPOTA(parkRef: parkRef, parkQSOs: parkQSOs)
            totalUploaded += result.uploaded
            totalFailed += result.failed
        }

        // Log final state
        await MainActor.run {
            SyncDebugLog.shared.info(
                "POTA upload complete: \(totalUploaded) uploaded, \(totalFailed) failed",
                service: .pota
            )
        }

        return totalUploaded
    }

    /// Log POTA upload start with metadata filtering info
    private func logPOTAUploadStart(qsos: [QSO], realQsos: [QSO], parkCount: Int) async {
        let metadataCount = qsos.count - realQsos.count
        await MainActor.run {
            if metadataCount > 0 {
                SyncDebugLog.shared.debug(
                    "Filtered out \(metadataCount) metadata QSO(s) from POTA upload",
                    service: .pota
                )
            }
            SyncDebugLog.shared.debug(
                "POTA upload: \(realQsos.count) QSO(s) across \(parkCount) park(s)",
                service: .pota
            )
        }
    }

    /// Upload QSOs for a single park to POTA
    private func uploadParkToPOTA(parkRef: String, parkQSOs: [QSO]) async -> (
        uploaded: Int, failed: Int
    ) {
        await MainActor.run {
            SyncDebugLog.shared.debug(
                "Uploading \(parkQSOs.count) QSO(s) to park \(parkRef)",
                service: .pota
            )
        }

        do {
            let result = try await potaClient.uploadActivationWithRecording(
                parkReference: parkRef,
                qsos: parkQSOs,
                modelContext: modelContext
            )

            if result.success {
                await MainActor.run {
                    for qso in parkQSOs {
                        qso.markPresent(in: .pota, context: modelContext)
                    }
                    SyncDebugLog.shared.debug(
                        "Park \(parkRef): \(result.qsosAccepted) QSO(s) accepted",
                        service: .pota
                    )
                }
                return (uploaded: result.qsosAccepted, failed: 0)
            } else {
                await MainActor.run {
                    SyncDebugLog.shared.warning(
                        "Park \(parkRef): upload returned success=false",
                        service: .pota
                    )
                    logFailedQSOs(parkQSOs, reason: "upload returned success=false")
                }
                return (uploaded: 0, failed: parkQSOs.count)
            }
        } catch {
            await MainActor.run {
                SyncDebugLog.shared.error(
                    "Park \(parkRef): \(error.localizedDescription)",
                    service: .pota
                )
                logFailedQSOs(parkQSOs, reason: error.localizedDescription)
            }
            return (uploaded: 0, failed: parkQSOs.count)
        }
    }
}
