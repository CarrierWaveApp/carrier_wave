// swiftlint:disable file_length

import CarrierWaveCore
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
                // Separate valid QSOs from those with missing required fields
                let (validQSOs, invalidQSOs) = partitionQSOsByValidity(qrzQSOs)
                await logQSOsWithMissingFields(invalidQSOs, service: .qrz)

                if !validQSOs.isEmpty {
                    await logPendingQSOs(validQSOs, service: .qrz)
                    let (service, result) = await uploadQRZBatch(qsos: validQSOs, timeout: timeout)
                    results[service] = result
                }
            }
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
        if clublogClient.isConfigured {
            let clublogQSOs = qsosNeedingUpload?
                .filter { $0.needsUpload(to: .clublog) } ?? []
            if !clublogQSOs.isEmpty {
                let (validQSOs, invalidQSOs) = partitionQSOsByValidity(clublogQSOs)
                await logQSOsWithMissingFields(invalidQSOs, service: .clublog)

                if !validQSOs.isEmpty {
                    await logPendingQSOs(validQSOs, service: .clublog)
                    let (service, result) = await uploadClubLogBatch(
                        qsos: validQSOs, timeout: timeout
                    )
                    results[service] = result
                }
            }
        }

        return (results: results, potaMaintenanceSkipped: potaMaintenanceSkipped)
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

    /// Partition QSOs into valid (uploadable) and invalid (missing required fields)
    private func partitionQSOsByValidity(_ qsos: [QSO]) -> (valid: [QSO], invalid: [QSO]) {
        let grouped = Dictionary(grouping: qsos) { $0.hasRequiredFieldsForUpload }
        return (valid: grouped[true] ?? [], invalid: grouped[false] ?? [])
    }

    /// Log QSOs that can't be uploaded due to missing required fields
    private func logQSOsWithMissingFields(_ qsos: [QSO], service: ServiceType) async {
        guard !qsos.isEmpty else {
            return
        }
        await MainActor.run {
            SyncDebugLog.shared.actionRequired(
                "\(qsos.count) QSO(s) cannot upload to \(service.displayName) "
                    + "- edit in Logs to add missing band/frequency",
                service: service
            )
            for qso in qsos.prefix(5) {
                let dateStr = Self.debugDateFormatter.string(from: qso.timestamp)
                var issues: [String] = []
                if qso.band.isEmpty || qso.band == "Unknown" {
                    issues.append("no band")
                }
                if qso.frequency == nil {
                    issues.append("no frequency")
                }
                SyncDebugLog.shared.actionRequired(
                    "  \(qso.callsign) @ \(dateStr) (\(issues.joined(separator: ", ")))",
                    service: service
                )
            }
            if qsos.count > 5 {
                SyncDebugLog.shared.actionRequired(
                    "  ... and \(qsos.count - 5) more", service: service
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
            for qso in qsos.prefix(10) {
                let dateStr = Self.debugDateFormatter.string(from: qso.timestamp)
                let park = qso.parkReference.map { " park=\($0)" } ?? ""
                SyncDebugLog.shared.debug(
                    "  - \(qso.callsign) @ \(dateStr) | \(qso.band) \(qso.mode)\(park)",
                    service: service
                )
            }
            if qsos.count > 10 {
                SyncDebugLog.shared.debug(
                    "  ... and \(qsos.count - 10) more pending", service: service
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
                        presence.isSubmitted = true
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
        let uploadStartTime = Date()

        // Filter out metadata pseudo-modes before processing
        let realQsos = qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }

        // Expand multi-park QSOs: each QSO with "US-1044, US-3791" becomes entries for both parks
        // This handles two-fer, three-fer, etc. activations
        var expandedByPark: [String: [QSO]] = [:]
        for qso in realQsos {
            guard let parkRef = qso.parkReference, !parkRef.isEmpty else {
                continue
            }

            let parks = POTAClient.splitParkReferences(parkRef)
            for park in parks {
                expandedByPark[park, default: []].append(qso)
            }
        }

        var totalUploaded = 0
        var totalFailed = 0

        await logPOTAUploadStart(qsos: qsos, realQsos: realQsos, parkCount: expandedByPark.count)

        for (parkRef, parkQSOs) in expandedByPark {
            let result = await uploadParkToPOTA(parkRef: parkRef, parkQSOs: parkQSOs)
            totalUploaded += result.uploaded
            totalFailed += result.failed
        }

        // Log final state with total timing
        let totalDurationMs = Int(Date().timeIntervalSince(uploadStartTime) * 1_000)
        await MainActor.run {
            SyncDebugLog.shared.info(
                "POTA upload complete: \(totalUploaded) uploaded, \(totalFailed) failed "
                    + "across \(expandedByPark.count) park(s) in \(totalDurationMs)ms",
                service: .pota
            )
        }

        return totalUploaded
    }

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

            let dateStr = Self.debugDateFormatter.string(from: qso.timestamp)
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

    // MARK: - Club Log Upload

    private func uploadClubLogBatch(qsos: [QSO], timeout: TimeInterval) async -> (
        ServiceType, Result<Int, Error>
    ) {
        await MainActor.run { self.syncPhase = .uploading(service: .clublog) }
        do {
            let result = try await withTimeout(seconds: timeout, service: .clublog) {
                try await self.uploadToClubLog(qsos: qsos)
            }
            return (.clublog, .success(result.uploaded))
        } catch {
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
