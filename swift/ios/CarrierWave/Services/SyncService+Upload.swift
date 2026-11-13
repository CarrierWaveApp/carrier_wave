import CarrierWaveData
import Foundation
import SwiftData

// MARK: - SyncService Upload Methods

extension SyncService {
    func uploadToAllDestinations() async -> (
        results: [ServiceType: Result<Int, Error>], potaMaintenanceSkipped: Bool
    ) {
        let qsosNeedingUpload: [QSO]?
        do {
            qsosNeedingUpload = try fetchQSOsNeedingUpload()
        } catch {
            await MainActor.run {
                SyncDebugLog.shared.error(
                    "Failed to fetch QSOs needing upload: \(error.localizedDescription)",
                    service: nil
                )
            }
            qsosNeedingUpload = nil
        }

        let timeout = syncTimeoutSeconds
        var results: [ServiceType: Result<Int, Error>] = [:]

        await logPendingUploads(qsosNeedingUpload)

        // Confirm with user if large upload detected
        if await shouldCancelExport(qsosNeedingUpload: qsosNeedingUpload) {
            return (results: results, potaMaintenanceSkipped: false)
        }

        // QRZ upload
        if let qrzResult = await uploadQRZIfConfigured(
            qsosNeedingUpload: qsosNeedingUpload, timeout: timeout
        ) {
            results[.qrz] = qrzResult
        }

        // POTA upload is user-driven via ADIFExportSheet "Upload to POTA"
        // — automatic uploads were removed to reduce POTA volunteer triage load.

        // Club Log: "Coming Soon" — not yet configurable as a sync source

        // eQSL upload
        if let eqslResult = await uploadEQSLIfConfigured(
            qsosNeedingUpload: qsosNeedingUpload, timeout: timeout
        ) {
            results[.eqsl] = eqslResult
        }

        // Record diagnostics for failures, clear for successes
        await recordUploadDiagnostics(results: results, qsosNeedingUpload: qsosNeedingUpload)

        return (results: results, potaMaintenanceSkipped: false)
    }

    /// Record diagnostics for upload results and clear diagnostics for successful services.
    private func recordUploadDiagnostics(
        results: [ServiceType: Result<Int, Error>],
        qsosNeedingUpload: [QSO]?
    ) async {
        let store = UploadDiagnosticStore.shared
        store.clearStale()

        for (service, result) in results {
            switch result {
            case .success:
                store.clearForService(service)
            case let .failure(error):
                let affected = qsosNeedingUpload?
                    .filter { $0.needsUpload(to: service) }.count ?? 0
                let diagnostic = UploadErrorClassifier.classify(
                    error: error, service: service, affectedCount: affected
                )
                store.record(diagnostic)
            }
        }

        // Report error telemetry if community features are enabled
        if store.hasIssues,
           UserDefaults.standard.bool(forKey: "activitiesServerEnabled")
        {
            let client = ActivitiesClient()
            await client.reportUploadErrors(store.diagnostics)
        }
    }

    /// Check if user wants to cancel a large export
    private func shouldCancelExport(qsosNeedingUpload: [QSO]?) async -> Bool {
        guard let qsos = qsosNeedingUpload,
              qsos.count >= SyncExportConfirmation.threshold
        else {
            return false
        }
        let uploadCounts = countUploadsByService(qsos)
        let shouldProceed = await requestExportConfirmation(
            uploadByService: uploadCounts
        )
        if !shouldProceed {
            await MainActor.run {
                SyncDebugLog.shared.info(
                    "User cancelled upload (\(qsos.count) QSOs)",
                    service: nil
                )
            }
            return true
        }
        return false
    }

    /// Upload to QRZ if configured, with debug logging
    private func uploadQRZIfConfigured(
        qsosNeedingUpload: [QSO]?, timeout: TimeInterval
    ) async -> Result<Int, Error>? {
        guard isUploadEnabled(for: .qrz) else {
            return nil
        }
        let mappings = qrzClient.getCallsignMappings()
        guard !mappings.isEmpty else {
            await MainActor.run {
                SyncDebugLog.shared.debug(
                    "QRZ upload skipped: no callsign mappings configured",
                    service: .qrz
                )
            }
            return nil
        }

        let qrzQSOs = qsosNeedingUpload?.filter { $0.needsUpload(to: .qrz) } ?? []
        guard !qrzQSOs.isEmpty else {
            await MainActor.run {
                SyncDebugLog.shared.debug(
                    "QRZ upload skipped: no QSOs need upload",
                    service: .qrz
                )
            }
            return nil
        }

        let (validQSOs, invalidQSOs) = partitionQSOsByValidity(qrzQSOs)
        await logQSOsWithMissingFields(invalidQSOs, service: .qrz)

        guard !validQSOs.isEmpty else {
            return nil
        }

        await logPendingQSOs(validQSOs, service: .qrz)
        let (_, result) = await uploadQRZBatch(qsos: validQSOs, timeout: timeout)
        return result
    }

    /// Log failed QSOs for debugging (call from MainActor)
    @MainActor
    func logFailedQSOs(_ qsos: [QSO], reason: String) {
        let callsigns = qsos.prefix(5).map(\.callsign).joined(separator: ", ")
        let more = qsos.count > 5 ? " (+\(qsos.count - 5) more)" : ""
        SyncDebugLog.shared.debug(
            "  Failed: \(callsigns)\(more) (\(reason))", service: .pota
        )
    }

    /// Mark QSOs with invalid park references as permanently rejected
    func rejectInvalidParkQSOs(parkRef: String, parkQSOs: [QSO], durationMs: Int) async {
        await MainActor.run {
            SyncDebugLog.shared.error(
                "Park \(parkRef): invalid park reference - marking \(parkQSOs.count) "
                    + "QSO(s) as rejected (\(durationMs)ms)",
                service: .pota
            )
            let build = ServicePresence.currentAppBuild
            for qso in parkQSOs {
                if let presence = qso.potaPresence(forPark: parkRef) {
                    presence.needsUpload = false
                    presence.uploadRejected = true
                    presence.rejectedAtBuild = build
                } else if let legacyPresence = qso.servicePresence.first(where: {
                    $0.serviceType == .pota && $0.parkReference == nil
                }) {
                    legacyPresence.needsUpload = false
                    legacyPresence.uploadRejected = true
                    legacyPresence.rejectedAtBuild = build
                }
            }
            logFailedQSOs(parkQSOs, reason: "Invalid park reference format")

            // Record diagnostic for invalid park references
            UploadDiagnosticStore.shared.record(
                UploadErrorClassifier.validationDiagnostic(
                    service: .pota,
                    message: "Park \(parkRef): invalid reference format",
                    guidance: "Park reference \"\(parkRef)\" is not valid. "
                        + "Expected format: XX-1234 (e.g., US-0001).",
                    affectedCount: parkQSOs.count
                )
            )
        }
    }

    private func uploadQRZBatch(qsos: [QSO], timeout: TimeInterval) async -> (
        ServiceType, Result<Int, Error>
    ) {
        await MainActor.run {
            self.syncPhase = .uploading(service: .qrz)
            self.serviceSyncStates[.qrz] = .uploading
        }
        do {
            let result = try await withTimeout(seconds: timeout, service: .qrz) {
                try await self.uploadToQRZ(qsos: qsos)
            }
            let downloadedCount = serviceSyncStates[.qrz]?.downloadedCount ?? 0
            await MainActor.run {
                self.serviceSyncStates[.qrz] = .complete(
                    downloaded: downloadedCount, uploaded: result.uploaded
                )
            }
            return (.qrz, .success(result.uploaded))
        } catch {
            await MainActor.run {
                self.serviceSyncStates[.qrz] = .error(error.localizedDescription)
            }
            return (.qrz, .failure(error))
        }
    }

    func fetchQSOsNeedingUpload() throws -> [QSO] {
        // Query from ServicePresence side — only loads records with needsUpload=true
        // instead of fetching all 50k+ QSOs and filtering in memory.
        let presenceDescriptor = BoundedDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { $0.needsUpload == true },
            limit: BoundedDescriptor<ServicePresence>.maxLimit
        )
        var pendingPresence = try modelContext.boundedFetch(presenceDescriptor)

        // Also include version-gated retries: QSOs rejected by an older build
        // that should be retried now that a new version is running.
        let currentBuild = ServicePresence.currentAppBuild
        let retryDescriptor = BoundedDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> {
                $0.uploadRejected == true
                    && $0.rejectedAtBuild != nil
                    && $0.rejectedAtBuild != currentBuild
            },
            limit: BoundedDescriptor<ServicePresence>.maxLimit
        )
        let retryPresence = try modelContext.boundedFetch(retryDescriptor)
        for presence in retryPresence {
            presence.uploadRejected = false
            presence.rejectedAtBuild = nil
            presence.needsUpload = true
        }
        pendingPresence.append(contentsOf: retryPresence)

        let primaryCallsign = CallsignAliasService.shared.getCurrentCallsign()?.uppercased()
        var seen = Set<PersistentIdentifier>()
        var result: [QSO] = []

        for presence in pendingPresence {
            guard let qso = presence.qso,
                  !qso.isHidden,
                  seen.insert(qso.persistentModelID).inserted
            else {
                continue
            }
            // Skip club station QSOs — user's sync accounts are tied to their personal call
            if qso.stationCallsign != nil {
                continue
            }
            let qsoCallsign = qso.myCallsign.uppercased()
            if qsoCallsign.isEmpty || primaryCallsign == nil || qsoCallsign == primaryCallsign {
                result.append(qso)
            }
        }
        return result
    }

    func uploadToQRZ(qsos: [QSO]) async throws -> (uploaded: Int, skipped: Int) {
        let uploadResult = try await qrzClient.uploadQSOs(qsos)

        // Re-fetch confirmed QSOs by PersistentIdentifier for fresh model access.
        // The upload loop yields between requests, so original references may be stale.
        for persistentID in uploadResult.confirmedIDs {
            guard let qso = modelContext.model(for: persistentID) as? QSO else {
                continue
            }
            if let presence = qso.presence(for: .qrz) {
                // CAR-244: only dirty when state actually changes. Refreshing
                // `lastConfirmedAt` alone is a heartbeat that shouldn't trigger
                // a CloudKit roundtrip on every upload pass.
                let stateChanged = !presence.isPresent || presence.needsUpload
                presence.needsUpload = false
                presence.isPresent = true
                presence.lastConfirmedAt = Date()
                if stateChanged {
                    presence.cloudDirtyFlag = true
                }
            }
            if let logId = uploadResult.logIdsByPersistentID[persistentID] {
                qso.qrzLogId = logId
            }
        }

        // Warn user if QSOs were skipped due to callsign mismatch
        if uploadResult.skipped > 0 {
            let callsign = qrzClient.getCallsign() ?? "unknown"
            SyncDebugLog.shared.warning(
                "Skipped \(uploadResult.skipped) QSO(s) from other callsigns "
                    + "(QRZ account: \(callsign))",
                service: .qrz
            )
        }

        // Log final state
        SyncDebugLog.shared.info(
            "QRZ upload complete: \(uploadResult.uploaded) uploaded, "
                + "\(uploadResult.duplicates) dupes, \(uploadResult.failed) failed, "
                + "\(uploadResult.skipped) skipped",
            service: .qrz
        )

        return (uploaded: uploadResult.uploaded, skipped: uploadResult.skipped)
    }
}
