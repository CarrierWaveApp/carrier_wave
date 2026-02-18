import CarrierWaveCore
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
        if let qrzResult = await uploadQRZIfConfigured(
            qsosNeedingUpload: qsosNeedingUpload, timeout: timeout
        ) {
            results[.qrz] = qrzResult
        }

        // POTA upload
        let potaResult = await uploadPOTAIfConfigured(
            qsosNeedingUpload: qsosNeedingUpload, timeout: timeout
        )
        if let result = potaResult.result {
            results[.pota] = result
        }
        potaMaintenanceSkipped = potaResult.maintenanceSkipped

        // Club Log upload
        if let clublogResult = await uploadClubLogIfConfigured(
            qsosNeedingUpload: qsosNeedingUpload, timeout: timeout
        ) {
            results[.clublog] = clublogResult
        }

        return (results: results, potaMaintenanceSkipped: potaMaintenanceSkipped)
    }

    /// Upload to QRZ if configured, with debug logging
    private func uploadQRZIfConfigured(
        qsosNeedingUpload: [QSO]?, timeout: TimeInterval
    ) async -> Result<Int, Error>? {
        guard qrzClient.hasApiKey() else {
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

    /// Upload to POTA if configured, with detailed debug logging
    private func uploadPOTAIfConfigured(
        qsosNeedingUpload: [QSO]?, timeout: TimeInterval
    ) async -> (result: Result<Int, Error>?, maintenanceSkipped: Bool) {
        // Use isConfigured to allow upload even if token expired - ensureValidToken will re-auth
        guard potaAuthService.isConfigured else {
            await MainActor.run {
                SyncDebugLog.shared.debug(
                    "POTA upload skipped: not configured (no stored credentials)",
                    service: .pota
                )
            }
            return (result: nil, maintenanceSkipped: false)
        }

        await MainActor.run {
            let isAuthed = potaAuthService.isAuthenticated
            let hasToken = potaAuthService.currentToken != nil
            let expired = potaAuthService.currentToken?.isExpired ?? false
            SyncDebugLog.shared.debug(
                "POTA auth state: configured=true, authenticated=\(isAuthed), "
                    + "hasToken=\(hasToken), tokenExpired=\(expired)",
                service: .pota
            )
        }

        if POTAClient.isInMaintenanceWindow() {
            await MainActor.run {
                SyncDebugLog.shared.info("POTA upload skipped: maintenance window", service: .pota)
            }
            return (result: nil, maintenanceSkipped: true)
        }

        return await executePOTAUpload(qsosNeedingUpload: qsosNeedingUpload, timeout: timeout)
    }

    /// Execute POTA upload after preconditions are met
    private func executePOTAUpload(
        qsosNeedingUpload: [QSO]?, timeout: TimeInterval
    ) async -> (result: Result<Int, Error>?, maintenanceSkipped: Bool) {
        let potaQSOs =
            qsosNeedingUpload?.filter {
                $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
            } ?? []

        await MainActor.run {
            let totalNeeding = qsosNeedingUpload?.filter { $0.needsUpload(to: .pota) }.count ?? 0
            SyncDebugLog.shared.info(
                "POTA upload candidates: \(totalNeeding) need upload, "
                    + "\(potaQSOs.count) have park ref",
                service: .pota
            )
        }

        let noPark =
            qsosNeedingUpload?.filter {
                $0.needsUpload(to: .pota) && ($0.parkReference?.isEmpty ?? true)
            } ?? []

        guard !potaQSOs.isEmpty else {
            await logPOTAQSOsWithoutPark(noPark)
            return (result: nil, maintenanceSkipped: false)
        }

        await logPendingQSOs(potaQSOs, service: .pota)
        let (_, result) = await uploadPOTABatch(qsos: potaQSOs, timeout: timeout)
        await logPOTAQSOsWithoutPark(noPark)

        return (result: result, maintenanceSkipped: false)
    }

    /// Log QSOs that need POTA upload but have no park reference
    private func logPOTAQSOsWithoutPark(_ qsos: [QSO]) async {
        guard !qsos.isEmpty else {
            return
        }
        let callsigns = qsos.prefix(5).map(\.callsign).joined(separator: ", ")
        let more = qsos.count > 5 ? " (+\(qsos.count - 5) more)" : ""
        await MainActor.run {
            SyncDebugLog.shared.warning(
                "\(qsos.count) QSO(s) need POTA upload but have no park reference: "
                    + "\(callsigns)\(more)",
                service: .pota
            )
        }
    }

    /// Log failed QSOs for debugging (call from MainActor)
    @MainActor
    private func logFailedQSOs(_ qsos: [QSO], reason: String) {
        let callsigns = qsos.prefix(5).map(\.callsign).joined(separator: ", ")
        let more = qsos.count > 5 ? " (+\(qsos.count - 5) more)" : ""
        SyncDebugLog.shared.debug(
            "  Failed: \(callsigns)\(more) (\(reason))", service: .pota
        )
    }

    /// Mark QSOs with invalid park references as permanently rejected
    private func rejectInvalidParkQSOs(parkRef: String, parkQSOs: [QSO], durationMs: Int) async {
        await MainActor.run {
            SyncDebugLog.shared.error(
                "Park \(parkRef): invalid park reference - marking \(parkQSOs.count) "
                    + "QSO(s) as rejected (\(durationMs)ms)",
                service: .pota
            )
            for qso in parkQSOs {
                if let presence = qso.potaPresence(forPark: parkRef) {
                    presence.needsUpload = false
                    presence.uploadRejected = true
                } else if let legacyPresence = qso.servicePresence.first(where: {
                    $0.serviceType == .pota && $0.parkReference == nil
                }) {
                    legacyPresence.needsUpload = false
                    legacyPresence.uploadRejected = true
                }
            }
            logFailedQSOs(parkQSOs, reason: "Invalid park reference format")
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
            // Never upload hidden (soft-deleted) QSOs
            guard !qso.isHidden else {
                return false
            }
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
        let uploadResult = try await qrzClient.uploadQSOs(qsos)

        // Mark only QSOs confirmed by QRZ (per-QSO result tracking)
        await MainActor.run {
            for index in uploadResult.confirmedIndices {
                let qso = qsos[index]
                if let presence = qso.presence(for: .qrz) {
                    presence.needsUpload = false
                    presence.isPresent = true
                    presence.lastConfirmedAt = Date()
                }
            }
        }

        // Warn user if QSOs were skipped due to callsign mismatch
        if uploadResult.skipped > 0 {
            let callsign = qrzClient.getCallsign() ?? "unknown"
            await MainActor.run {
                SyncDebugLog.shared.warning(
                    "Skipped \(uploadResult.skipped) QSO(s) from other callsigns "
                        + "(QRZ account: \(callsign))",
                    service: .qrz
                )
            }
        }

        // Log final state
        await MainActor.run {
            SyncDebugLog.shared.info(
                "QRZ upload complete: \(uploadResult.uploaded) uploaded, "
                    + "\(uploadResult.duplicates) dupes, \(uploadResult.failed) failed, "
                    + "\(uploadResult.skipped) skipped",
                service: .qrz
            )
        }

        return (uploaded: uploadResult.uploaded, skipped: uploadResult.skipped)
    }

    func uploadToPOTA(qsos: [QSO]) async throws -> Int {
        let uploadStartTime = Date()

        // Filter out metadata pseudo-modes before processing
        let realQsos = qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }

        // Group by (park, UTC date) so each upload matches a single POTA activation.
        // Without date grouping, multi-date uploads create jobs whose firstQSO date
        // only covers one date, causing the reconciliation to reset QSOs from other
        // dates back to needsUpload (producing duplicate uploads on every sync).
        var expandedByParkAndDate: [String: [QSO]] = [:]
        for qso in realQsos {
            guard let parkRef = qso.parkReference, !parkRef.isEmpty else {
                continue
            }

            let parks = POTAClient.splitParkReferences(parkRef)
            let dateStr = Self.utcDateFormatter.string(from: qso.timestamp)
            for park in parks {
                let key = "\(park)|\(dateStr)"
                expandedByParkAndDate[key, default: []].append(qso)
            }
        }

        var totalUploaded = 0
        var totalFailed = 0
        let parkRefs = Set(expandedByParkAndDate.keys.compactMap {
            $0.split(separator: "|").first.map(String.init)
        })

        await logPOTAUploadStart(
            qsos: qsos, realQsos: realQsos, parkCount: parkRefs.count
        )

        for (key, parkQSOs) in expandedByParkAndDate {
            let parkRef = String(key.split(separator: "|").first ?? "")
            let result = await uploadParkToPOTA(parkRef: parkRef, parkQSOs: parkQSOs)
            totalUploaded += result.uploaded
            totalFailed += result.failed
        }

        // Log final state with total timing
        let totalDurationMs = Int(Date().timeIntervalSince(uploadStartTime) * 1_000)
        await MainActor.run {
            SyncDebugLog.shared.info(
                "POTA upload complete: \(totalUploaded) uploaded, \(totalFailed) failed "
                    + "across \(expandedByParkAndDate.count) activation(s) in "
                    + "\(totalDurationMs)ms",
                service: .pota
            )
        }

        return totalUploaded
    }

    /// UTC date formatter for grouping QSOs by activation date
    private static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Log POTA upload start with metadata filtering info and content summary
    private func logPOTAUploadStart(qsos: [QSO], realQsos: [QSO], parkCount: Int) async {
        let metadataCount = qsos.count - realQsos.count
        await MainActor.run {
            if metadataCount > 0 {
                SyncDebugLog.shared.debug(
                    "Filtered out \(metadataCount) metadata QSO(s) from POTA upload",
                    service: .pota
                )
            }
            let bands = Set(realQsos.map(\.band)).sorted().joined(separator: ", ")
            let modes = Set(realQsos.map(\.mode)).sorted().joined(separator: ", ")
            SyncDebugLog.shared.debug(
                "POTA upload: \(realQsos.count) QSO(s) across \(parkCount) park(s) "
                    + "bands=[\(bands)] modes=[\(modes)]",
                service: .pota
            )
        }
    }

    /// Upload QSOs for a single park to POTA (handles both single-park and two-fer QSOs)
    private func uploadParkToPOTA(parkRef: String, parkQSOs: [QSO]) async -> (
        uploaded: Int, failed: Int
    ) {
        let parkStartTime = Date()
        await MainActor.run {
            SyncDebugLog.shared.info(
                "Starting upload of \(parkQSOs.count) QSO(s) to park \(parkRef)",
                service: .pota
            )
        }

        do {
            let result = try await potaClient.uploadActivationWithRecording(
                parkReference: parkRef,
                qsos: parkQSOs,
                modelContext: modelContext
            )
            let parkDurationMs = Int(Date().timeIntervalSince(parkStartTime) * 1_000)

            if result.success {
                markParkQSOsSubmitted(
                    parkRef: parkRef, parkQSOs: parkQSOs,
                    result: result, durationMs: parkDurationMs
                )
                return (uploaded: result.qsosAccepted, failed: 0)
            } else {
                await MainActor.run {
                    SyncDebugLog.shared.warning(
                        "Park \(parkRef): upload returned success=false (\(parkDurationMs)ms)",
                        service: .pota
                    )
                    logFailedQSOs(parkQSOs, reason: "upload returned success=false")
                }
                return (uploaded: 0, failed: parkQSOs.count)
            }
        } catch POTAError.invalidParkReference {
            let parkDurationMs = Int(Date().timeIntervalSince(parkStartTime) * 1_000)
            await rejectInvalidParkQSOs(
                parkRef: parkRef, parkQSOs: parkQSOs, durationMs: parkDurationMs
            )
            return (uploaded: 0, failed: parkQSOs.count)
        } catch {
            let parkDurationMs = Int(Date().timeIntervalSince(parkStartTime) * 1_000)
            await MainActor.run {
                SyncDebugLog.shared.error(
                    "Park \(parkRef): \(error.localizedDescription) (\(parkDurationMs)ms)",
                    service: .pota
                )
                logFailedQSOs(parkQSOs, reason: error.localizedDescription)
            }
            return (uploaded: 0, failed: parkQSOs.count)
        }
    }

    /// Mark QSOs as submitted after successful park upload and log state transitions
    @MainActor
    private func markParkQSOsSubmitted(
        parkRef: String, parkQSOs: [QSO],
        result: POTAUploadResult, durationMs: Int
    ) {
        for qso in parkQSOs {
            let beforeState =
                qso.potaPresence(forPark: parkRef).map {
                    "isPresent=\($0.isPresent), isSubmitted=\($0.isSubmitted), "
                        + "needsUpload=\($0.needsUpload)"
                } ?? "no presence"
            qso.markSubmittedToPark(parkRef, context: modelContext)
            let afterState =
                qso.potaPresence(forPark: parkRef).map {
                    "isPresent=\($0.isPresent), isSubmitted=\($0.isSubmitted), "
                        + "needsUpload=\($0.needsUpload)"
                } ?? "no presence"

            let dateStr = Self.uploadDebugDateFormatter.string(from: qso.timestamp)
            SyncDebugLog.shared.debug(
                "markSubmittedToPark \(parkRef): \(qso.callsign) @ \(dateStr) "
                    + "[\(beforeState)] -> [\(afterState)]",
                service: .pota
            )
        }
        SyncDebugLog.shared.info(
            "Park \(parkRef): \(result.qsosAccepted) QSO(s) accepted, "
                + "\(parkQSOs.count) marked submitted in \(durationMs)ms. "
                + "message=\(result.message ?? "nil")",
            service: .pota
        )
    }
}
