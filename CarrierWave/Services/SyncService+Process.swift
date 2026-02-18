// swiftlint:disable file_length

import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - SyncService Process Methods

extension SyncService {
    struct ProcessResult {
        // MARK: Internal

        let created: Int
        let merged: Int
        let createdQSOIds: [UUID]

        /// Fetch created QSOs from context (for activity detection).
        /// Call this on the main actor after processing completes.
        /// Limited to most recent QSOs to avoid UI hang on large syncs.
        func fetchCreatedQSOs(from context: ModelContext) -> [QSO] {
            guard !createdQSOIds.isEmpty else {
                return []
            }

            // For large syncs, skip activity detection to avoid UI hang
            // Activity detection is most useful for small incremental syncs
            guard createdQSOIds.count <= Self.maxActivityDetectionQSOs else {
                return []
            }

            // Fetch in batches to avoid slow ids.contains() predicate
            var results: [QSO] = []
            for id in createdQSOIds {
                var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if let qso = try? context.fetch(descriptor).first {
                    results.append(qso)
                }
            }
            return results
        }

        // MARK: Private

        /// Maximum QSOs to fetch for activity detection (avoid UI hang on large syncs)
        private static let maxActivityDetectionQSOs = 100
    }

    /// Background actor for heavy QSO processing work.
    private static let processingActor = QSOProcessingActor()

    /// Process downloaded QSOs on a background thread to avoid blocking the UI.
    /// Returns counts and created QSO IDs; use fetchCreatedQSOs() to get actual QSO objects.
    func processDownloadedQSOsAsync(_ fetched: [FetchedQSO]) async throws -> ProcessResult {
        let result = try await Self.processingActor.processDownloadedQSOs(
            fetched, container: modelContext.container
        ) { progress in
            Task { @MainActor in
                self.syncProgress.updateProcessing(
                    processed: progress.processed, total: progress.total, phase: progress.phase
                )
            }
        }
        for message in result.logMessages {
            SyncDebugLog.shared.info(message)
        }
        return ProcessResult(
            created: result.created, merged: result.merged,
            createdQSOIds: result.createdQSOIds
        )
    }

    /// Reconcile QRZ presence records against what QRZ actually returned.
    /// Now runs on background thread to avoid blocking UI.
    /// Returns the number of presence records reset to needsUpload.
    @discardableResult
    func reconcileQRZPresenceAsync(downloadedKeys: Set<String>) async throws -> Int {
        let aliasService = CallsignAliasService.shared
        let userCallsigns = aliasService.getAllUserCallsigns()

        return try await Self.processingActor.reconcileQRZPresence(
            downloadedKeys: downloadedKeys,
            userCallsigns: userCallsigns,
            container: modelContext.container
        )
    }

    /// Reconcile POTA presence records against upload job log.
    /// Fetches jobs from POTA API, then checks every POTA ServicePresence record:
    /// - isPresent=true with no completed job → reset to needsUpload=true
    /// - isSubmitted=true with completed job → confirm as uploaded
    /// - isSubmitted=true with failed job → reset to needsUpload=true
    /// Returns the POTA reconciliation result, or nil if skipped/failed.
    @discardableResult
    func reconcilePOTAPresenceAsync() async
        -> QSOProcessingActor.POTAReconcileResult?
    {
        let debugLog = SyncDebugLog.shared

        guard potaAuthService.isConfigured else {
            debugLog.debug("POTA reconciliation skipped: not configured", service: .pota)
            return nil
        }

        do {
            let fetchStart = Date()
            let jobs = try await potaClient.fetchJobs()
            let fetchDurationMs = Int(Date().timeIntervalSince(fetchStart) * 1_000)
            let activationKeys = buildPOTAActivationKeys(from: jobs)

            debugLog.debug(
                "POTA reconciliation: fetched \(jobs.count) jobs in \(fetchDurationMs)ms, "
                    + "\(activationKeys.confirmed.count) confirmed, "
                    + "\(activationKeys.failed.count) failed, "
                    + "\(activationKeys.inProgress.count) in-progress",
                service: .pota
            )

            // Log each job's details for debugging
            let jobDateFormatter = DateFormatter()
            jobDateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            jobDateFormatter.timeZone = TimeZone(identifier: "UTC")
            for job in jobs {
                let submittedStr = jobDateFormatter.string(from: job.submitted)
                let processedStr = job.processed.map { jobDateFormatter.string(from: $0) } ?? "n/a"
                let firstQSOStr = job.firstQSO.map { jobDateFormatter.string(from: $0) } ?? "n/a"
                debugLog.debug(
                    "  Job #\(job.jobId): \(job.reference) status=\(job.status.displayName) "
                        + "callsign=\(job.callsignUsed ?? "nil") "
                        + "total=\(job.totalQsos) inserted=\(job.insertedQsos) "
                        + "submitted=\(submittedStr) processed=\(processedStr) "
                        + "firstQSO=\(firstQSOStr)",
                    service: .pota
                )
            }

            let result = try await Self.processingActor.reconcilePOTAPresence(
                activationKeys: activationKeys,
                container: modelContext.container
            )

            logPOTAReconcileResult(result)
            return result
        } catch {
            debugLog.error(
                "POTA reconciliation failed: \(error.localizedDescription)", service: .pota
            )
            return nil
        }
    }

    /// Classified POTA activation keys from the job log.
    /// Key format: "PARKREF|CALLSIGN|YYYY-MM-DD"
    struct POTAActivationKeys {
        /// Activations with completed or duplicate jobs — POTA has the QSOs
        var confirmed = Set<String>()
        /// Activations with failed jobs — need re-upload
        var failed = Set<String>()
        /// Activations with pending/processing jobs — maps key to submitted timestamp
        var inProgress = [String: Date]()
        /// Park+callsign pairs with nil-date completed jobs (all QSOs were duplicates).
        /// Format: "PARKREF|CALLSIGN". Used as fallback when no date-specific key matches
        /// a submitted presence — prevents orphan-reset loops for all-duplicate re-uploads.
        var nilDateConfirmed = Set<String>()
    }

    /// Build classified activation key sets from POTA jobs.
    /// In-progress keys map to the job's submitted timestamp for staleness checking.
    func buildPOTAActivationKeys(from jobs: [POTAJob]) -> POTAActivationKeys {
        var keys = POTAActivationKeys()

        for job in jobs {
            guard let callsign = job.callsignUsed else {
                continue
            }

            if let utcDate = job.utcDateString {
                let key = "\(job.reference.uppercased())|\(callsign.uppercased())|\(utcDate)"

                if job.status == .completed || job.status == .duplicate {
                    keys.confirmed.insert(key)
                } else if job.status.isFailure {
                    keys.failed.insert(key)
                } else {
                    keys.inProgress[key] = job.submitted
                }
            } else if job.status == .completed || job.status == .duplicate {
                // Nil-date completed jobs happen when all QSOs were duplicates
                // (POTA returns firstQSO=nil). Track by park+callsign so the
                // reconciliation doesn't orphan-reset submitted QSOs that POTA
                // already has.
                let parkCallsign =
                    "\(job.reference.uppercased())|\(callsign.uppercased())"
                keys.nilDateConfirmed.insert(parkCallsign)
            }
        }

        // Remove failed keys that also have a completed/duplicate job
        keys.failed.subtract(keys.confirmed)
        // Remove in-progress keys that also have a completed/duplicate job
        for key in keys.confirmed {
            keys.inProgress.removeValue(forKey: key)
        }
        return keys
    }

    /// Log the results of POTA presence reconciliation.
    private func logPOTAReconcileResult(_ result: QSOProcessingActor.POTAReconcileResult) {
        let debugLog = SyncDebugLog.shared
        if result.resetCount > 0 {
            debugLog.warning(
                "POTA reconciliation: reset \(result.resetCount) presence record(s) "
                    + "(DB said uploaded but no completed job found)",
                service: .pota
            )
        }
        if result.confirmedCount > 0 {
            debugLog.info(
                "POTA reconciliation: confirmed \(result.confirmedCount) submitted upload(s)",
                service: .pota
            )
        }
        if result.failedResetCount > 0 {
            debugLog.warning(
                "POTA reconciliation: reset \(result.failedResetCount) submitted upload(s) "
                    + "(job failed)",
                service: .pota
            )
        }
        if result.orphanResetCount > 0 {
            debugLog.warning(
                "POTA reconciliation: reset \(result.orphanResetCount) submitted upload(s) "
                    + "(no matching job found - upload was likely silently dropped)",
                service: .pota
            )
        }
        if result.inProgressCount > 0 {
            debugLog.info(
                "POTA reconciliation: \(result.inProgressCount) upload(s) still in-progress "
                    + "(pending/processing - waiting for POTA to finish)",
                service: .pota
            )
        }
        if result.staleResetCount > 0 {
            debugLog.warning(
                "POTA reconciliation: reset \(result.staleResetCount) submitted upload(s) "
                    + "(job pending/processing >30 min - considered stale)",
                service: .pota
            )
        }
        let totalChanges =
            result.resetCount + result.confirmedCount
                + result.failedResetCount + result.orphanResetCount
                + result.staleResetCount
        if totalChanges == 0, result.inProgressCount == 0 {
            debugLog.debug("POTA reconciliation: no changes needed", service: .pota)
        }
    }

    /// Compare local POTA QSOs against what POTA's API returned per-activation.
    /// Flags missing QSOs as needsUpload=true for re-upload.
    func repairPOTAGapsAsync(remoteQSOMap: POTARemoteQSOMap) async {
        do {
            let result = try await Self.processingActor.repairPOTAGaps(
                remoteQSOMap: remoteQSOMap,
                container: modelContext.container
            )
            if result.gapsFound > 0 {
                SyncDebugLog.shared.warning(
                    "POTA gap repair: checked \(result.activationsChecked) activations, "
                        + "found \(result.gapsFound) missing QSOs — flagged for re-upload",
                    service: .pota
                )
            } else {
                SyncDebugLog.shared.debug(
                    "POTA gap repair: checked \(result.activationsChecked) activations, no gaps",
                    service: .pota
                )
            }
        } catch {
            SyncDebugLog.shared.error("POTA gap repair failed: \(error)", service: .pota)
        }
    }

    /// Detect and repair QSOs missing ServicePresence records for a service.
    func repairOrphanedQSOsAsync(for service: ServiceType) async {
        let debugLog = SyncDebugLog.shared
        let aliasService = CallsignAliasService.shared
        let userCallsigns = aliasService.getAllUserCallsigns()

        do {
            let result = try await Self.processingActor.repairOrphanedQSOs(
                for: [service], userCallsigns: userCallsigns, container: modelContext.container
            )
            if result.orphanedQSOs.isEmpty {
                debugLog.debug(
                    "No orphaned QSOs found for \(service.displayName)", service: service
                )
            } else {
                let msg =
                    "Found \(result.orphanedQSOs.count) QSOs without \(service.displayName) "
                        + "presence - created \(result.repairedCount) ServicePresence records:"
                debugLog.warning(msg, service: service)
                let dateFmt = ISO8601DateFormatter()
                dateFmt.formatOptions = [.withInternetDateTime]
                for (idx, qso) in result.orphanedQSOs.prefix(10).enumerated() {
                    let ts = dateFmt.string(from: qso.timestamp)
                    let svcs = qso.missingServices.map(\.displayName).joined(separator: ", ")
                    let detail =
                        "  \(idx + 1). \(qso.callsign) \(qso.band) \(qso.mode) @ \(ts) "
                            + "(my: \(qso.myCallsign)) - missing: \(svcs)"
                    debugLog.warning(detail, service: service)
                }
                if result.orphanedQSOs.count > 10 {
                    debugLog.warning(
                        "  ... and \(result.orphanedQSOs.count - 10) more", service: service
                    )
                }
            }
        } catch {
            debugLog.error("Failed to repair orphaned QSOs: \(error)", service: service)
        }
    }

    /// Clear needsUpload flags on hidden (soft-deleted) QSOs.
    func clearHiddenQSOUploadFlagsAsync() async {
        do {
            let result = try await Self.processingActor.clearHiddenQSOUploadFlags(
                container: modelContext.container
            )
            if result.clearedCount > 0 {
                let msg =
                    "Cleared needsUpload on \(result.clearedCount) hidden (soft-deleted) QSO(s)"
                SyncDebugLog.shared.warning(msg)
            }
        } catch {
            SyncDebugLog.shared.error("Failed to clear hidden QSO upload flags: \(error)")
        }
    }

    /// Clear needsUpload flags on metadata pseudo-modes (WEATHER, SOLAR, NOTE from Ham2K PoLo).
    func clearMetadataUploadFlagsAsync() async {
        do {
            let result = try await Self.processingActor.clearMetadataUploadFlags(
                container: modelContext.container
            )
            if result.clearedCount > 0 {
                let msg =
                    "Cleared needsUpload on \(result.clearedCount) metadata QSO(s) (WEATHER/SOLAR/NOTE)"
                SyncDebugLog.shared.info(msg)
            }
        } catch {
            SyncDebugLog.shared.error("Failed to clear metadata upload flags: \(error)")
        }
    }

    /// Clear needsUpload flags on QSOs logged under non-primary callsigns.
    func clearNonPrimaryCallsignUploadFlagsAsync() async {
        let primaryCallsign = CallsignAliasService.shared.getCurrentCallsign()
        do {
            let result = try await Self.processingActor.clearNonPrimaryCallsignUploadFlags(
                primaryCallsign: primaryCallsign, container: modelContext.container
            )
            if result.clearedCount > 0 {
                let msg =
                    "Cleared needsUpload on \(result.clearedCount) QSO(s) from non-primary callsigns"
                SyncDebugLog.shared.info(msg)
                for (call, count) in result.byCallsign.sorted(by: { $0.value > $1.value }) {
                    SyncDebugLog.shared.debug("  - \(call): \(count) QSO(s)")
                }
            }
        } catch {
            SyncDebugLog.shared.error("Failed to clear non-primary callsign upload flags: \(error)")
        }
    }

    /// Clear bogus HAMRS needsUpload flags created when supportsUpload was incorrectly true.
    func clearBogusHamrsUploadFlagsAsync() async {
        do {
            let result = try await Self.processingActor.clearBogusHamrsUploadFlags(
                container: modelContext.container
            )
            if result.clearedCount > 0 {
                SyncDebugLog.shared.warning(
                    "Cleared \(result.clearedCount) bogus HAMRS needsUpload flag(s)"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Failed to clear HAMRS upload flags: \(error)")
        }
    }

    /// Repair QRZ ServicePresence records stuck in dead state
    /// (isPresent=false, needsUpload=false, not submitted, not rejected).
    func repairQRZDeadStateAsync() async {
        do {
            let result = try await Self.processingActor.repairQRZDeadStateQSOs(
                container: modelContext.container
            )
            if result.repairedCount > 0 {
                SyncDebugLog.shared.warning(
                    "Repaired \(result.repairedCount) QRZ dead-state QSO(s) "
                        + "(reset to needsUpload=true)"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Failed to repair QRZ dead-state QSOs: \(error)")
        }
    }

    /// Repair QSOs that have DXCC in rawADIF but not in the dxcc column.
    /// This backfills DXCC data for QSOs imported before the fix was applied.
    func repairMissingDXCCAsync() async {
        do {
            let result = try await Self.processingActor.repairMissingDXCC(
                container: modelContext.container
            )
            if result.repairedCount > 0 {
                let msg =
                    "Repaired DXCC on \(result.repairedCount) QSO(s) from rawADIF "
                        + "(scanned \(result.scannedCount))"
                SyncDebugLog.shared.info(msg)
            }
        } catch {
            SyncDebugLog.shared.error("Failed to repair missing DXCC: \(error)")
        }
    }

    /// Repair QSOs with leading/trailing whitespace in callsigns.
    /// Trims whitespace, then merges any resulting duplicates.
    func repairCallsignWhitespaceAsync() async {
        do {
            let result = try await Self.processingActor.repairCallsignWhitespace(
                container: modelContext.container
            )
            if result.trimmedCount > 0 || result.mergedCount > 0 {
                SyncDebugLog.shared.warning(
                    "Callsign whitespace repair: trimmed \(result.trimmedCount), "
                        + "merged \(result.mergedCount), deleted \(result.deletedCount)"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Failed to repair callsign whitespace: \(error)")
        }
    }

    /// Repair QRZ ServicePresence records stuck in isSubmitted=true state.
    /// QRZ uploads are synchronous — isSubmitted should have been isPresent.
    func repairQRZSubmittedStateAsync() async {
        do {
            let result = try await Self.processingActor.repairQRZSubmittedState(
                container: modelContext.container
            )
            if result.repairedCount > 0 {
                SyncDebugLog.shared.warning(
                    "Repaired \(result.repairedCount) QRZ ServicePresence record(s) "
                        + "stuck in isSubmitted state (promoted to isPresent)"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Failed to repair QRZ submitted state: \(error)")
        }
    }

    // MARK: - Legacy Synchronous Methods

    /// Synchronous version - prefer processDownloadedQSOsAsync for better UI responsiveness.
    func processDownloadedQSOs(_ fetched: [FetchedQSO]) throws -> ProcessResult {
        let debugLog = SyncDebugLog.shared

        // Group by deduplication key
        var byKey: [String: [FetchedQSO]] = [:]
        for qso in fetched {
            byKey[qso.deduplicationKey, default: []].append(qso)
        }

        // Count by source for diagnostics
        let breakdownStr = buildSourceBreakdown(fetched)
        debugLog.info("Processing \(fetched.count) QSOs: \(breakdownStr)")

        // Fetch existing QSOs
        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)
        let existingByKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }
        debugLog.info("Found \(existingQSOs.count) existing QSOs in database")

        var created = 0
        var merged = 0
        var createdQSOIds: [UUID] = []

        for (key, fetchedGroup) in byKey {
            if let existing = existingByKey[key]?.first {
                for fetchedQSO in fetchedGroup {
                    mergeIntoExisting(existing: existing, fetched: fetchedQSO)
                }
                merged += 1
            } else {
                let newQSO = createNewQSOFromGroup(fetchedGroup)
                createdQSOIds.append(newQSO.id)
                created += 1
            }
        }

        debugLog.info("Process result: created=\(created), merged=\(merged)")
        return ProcessResult(created: created, merged: merged, createdQSOIds: createdQSOIds)
    }

    private func buildSourceBreakdown(_ fetched: [FetchedQSO]) -> String {
        var sourceBreakdown: [ServiceType: Int] = [:]
        for qso in fetched {
            sourceBreakdown[qso.source, default: 0] += 1
        }
        return sourceBreakdown.map { "\($0.key.displayName)=\($0.value)" }.joined(separator: ", ")
    }

    @discardableResult
    private func createNewQSOFromGroup(_ fetchedGroup: [FetchedQSO]) -> QSO {
        let mergedFetched = mergeFetchedGroup(fetchedGroup)
        let newQSO = createQSO(from: mergedFetched)
        modelContext.insert(newQSO)

        // Create presence records for all sources that had this QSO
        let sources = Set(fetchedGroup.map(\.source))

        // Create presence record for ALL services
        for service in ServiceType.allCases {
            // POTA uploads only apply to QSOs where user was activating from a park
            let skipPOTAUpload = service == .pota && (newQSO.parkReference?.isEmpty ?? true)

            let presence =
                if sources.contains(service) {
                    // QSO came from this service - mark as present
                    ServicePresence.downloaded(from: service, qso: newQSO)
                } else if service.supportsUpload, !skipPOTAUpload {
                    // Bidirectional service without this QSO - needs upload
                    ServicePresence.needsUpload(to: service, qso: newQSO)
                } else {
                    // Download-only service without this QSO - not present, no upload needed
                    ServicePresence(serviceType: service, isPresent: false, qso: newQSO)
                }
            modelContext.insert(presence)
            newQSO.servicePresence.append(presence)
        }

        return newQSO
    }

    /// Reconcile QRZ presence records against what QRZ actually returned.
    /// Clears isPresent and sets needsUpload for QSOs that we thought were in QRZ but aren't.
    /// Uses callsign aliases to properly match QSOs logged under previous callsigns.
    func reconcileQRZPresence(downloadedKeys: Set<String>) async throws {
        let descriptor = FetchDescriptor<QSO>()
        let allQSOs = try modelContext.fetch(descriptor)

        // Get user's callsign aliases for matching
        let aliasService = await MainActor.run { CallsignAliasService.shared }
        let userCallsigns = await MainActor.run { aliasService.getAllUserCallsigns() }

        for qso in allQSOs {
            guard let presence = qso.presence(for: .qrz), presence.isPresent else {
                continue
            }

            // Check if QRZ returned this QSO or an equivalent one under a different user callsign
            let isPresent = isQSOPresentInDownloaded(
                qso: qso,
                downloadedKeys: downloadedKeys,
                userCallsigns: userCallsigns
            )

            if !isPresent {
                presence.isPresent = false
                presence.needsUpload = true
            }
        }
    }

    /// Check if a QSO is present in the downloaded set, considering callsign aliases.
    /// QRZ consolidates all QSOs under the user's current callsign, so a QSO logged under
    /// "KK4RBD" might appear in QRZ under "N9HO" if those are the same operator.
    private func isQSOPresentInDownloaded(
        qso: QSO,
        downloadedKeys: Set<String>,
        userCallsigns: Set<String>
    ) -> Bool {
        // First, check exact match
        if downloadedKeys.contains(qso.deduplicationKey) {
            return true
        }

        // If the QSO's myCallsign is one of the user's callsigns, check if any variant exists
        let myCallsign = qso.myCallsign.uppercased()
        guard !myCallsign.isEmpty, userCallsigns.contains(myCallsign) else {
            return false
        }

        // The deduplication key format is: "CALLSIGN|BAND|MODE|TIMESTAMP"
        // We need to check if the same contacted station exists under any user callsign variant
        // Since QRZ consolidates under current call, the key in downloadedKeys might differ
        // only in the ignored MYCALLSIGN part (which isn't in the dedup key anyway)

        // The deduplication key already ignores MYCALLSIGN (it uses contacted station),
        // so if the exact key isn't found, the QSO truly isn't present
        return false
    }

    /// Merge fetched QSO data into existing QSO (richest data wins)
    func mergeIntoExisting(existing: QSO, fetched: FetchedQSO) {
        existing.frequency = existing.frequency ?? fetched.frequency
        existing.rstSent = existing.rstSent.nonEmpty ?? fetched.rstSent
        existing.rstReceived = existing.rstReceived.nonEmpty ?? fetched.rstReceived
        existing.myGrid = existing.myGrid.nonEmpty ?? fetched.myGrid
        existing.theirGrid = existing.theirGrid.nonEmpty ?? fetched.theirGrid
        existing.parkReference = FetchedQSO.combineParkReferences(
            existing.parkReference,
            fetched.parkReference.flatMap { ParkReference.sanitizeMulti($0) }
        )
        existing.theirParkReference =
            existing.theirParkReference.nonEmpty
                ?? fetched.theirParkReference.flatMap { ParkReference.sanitize($0) }
        existing.notes = existing.notes.nonEmpty ?? fetched.notes
        existing.rawADIF = existing.rawADIF.nonEmpty ?? fetched.rawADIF
        existing.name = existing.name.nonEmpty ?? fetched.name
        existing.qth = existing.qth.nonEmpty ?? fetched.qth
        existing.state = existing.state.nonEmpty ?? fetched.state
        existing.country = existing.country.nonEmpty ?? fetched.country
        existing.power = existing.power ?? fetched.power
        existing.myRig = existing.myRig.nonEmpty ?? fetched.myRig
        existing.sotaRef = existing.sotaRef.nonEmpty ?? fetched.sotaRef

        // QRZ-specific: only update from QRZ source
        if fetched.source == .qrz {
            existing.qrzLogId = existing.qrzLogId ?? fetched.qrzLogId
            existing.qrzConfirmed = existing.qrzConfirmed || fetched.qrzConfirmed
            existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
            // DXCC from QRZ if we don't have one yet
            existing.dxcc = existing.dxcc ?? fetched.dxcc
        }

        // LoTW-specific: update confirmation status and DXCC
        if fetched.source == .lotw {
            if fetched.lotwConfirmed {
                existing.lotwConfirmed = true
                existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
            }
            // DXCC from LoTW is authoritative
            existing.dxcc = existing.dxcc ?? fetched.dxcc
        }

        // Update or create ServicePresence
        existing.markPresent(in: fetched.source, context: modelContext)
    }

    /// Update existing QSO with all fields from fetched data (for force re-download)
    func updateExistingQSO(existing: QSO, from fetched: FetchedQSO) {
        existing.frequency = fetched.frequency
        existing.rstSent = fetched.rstSent
        existing.rstReceived = fetched.rstReceived
        existing.myGrid = fetched.myGrid
        existing.theirGrid = fetched.theirGrid
        existing.parkReference = fetched.parkReference
        existing.theirParkReference = fetched.theirParkReference
        existing.notes = fetched.notes
        existing.rawADIF = fetched.rawADIF
        existing.name = fetched.name
        existing.qth = fetched.qth
        existing.state = fetched.state
        existing.country = fetched.country
        existing.power = fetched.power
        existing.myRig = fetched.myRig
        existing.sotaRef = fetched.sotaRef

        // QRZ-specific
        if fetched.source == .qrz {
            existing.qrzLogId = fetched.qrzLogId
            existing.qrzConfirmed = fetched.qrzConfirmed
            existing.lotwConfirmedDate = fetched.lotwConfirmedDate
            existing.dxcc = existing.dxcc ?? fetched.dxcc
        }

        // LoTW-specific
        if fetched.source == .lotw {
            existing.lotwConfirmed = fetched.lotwConfirmed
            existing.lotwConfirmedDate = fetched.lotwConfirmedDate
            existing.dxcc = fetched.dxcc
        }

        existing.markPresent(in: fetched.source, context: modelContext)
    }

    /// Reprocess fetched QSOs, updating existing ones instead of skipping
    func reprocessQSOs(_ fetched: [FetchedQSO]) throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Reprocessing \(fetched.count) QSOs (force re-download)")

        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)
        let existingByKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }

        var updated = 0
        var created = 0

        for fetchedQSO in fetched {
            let key = fetchedQSO.deduplicationKey
            if let existing = existingByKey[key]?.first {
                updateExistingQSO(existing: existing, from: fetchedQSO)
                updated += 1
            } else {
                let newQSO = createQSO(from: fetchedQSO)
                modelContext.insert(newQSO)
                createPresenceForNewQSO(newQSO, source: fetchedQSO.source)
                created += 1
            }
        }

        try modelContext.save()
        debugLog.info("Reprocess complete: updated=\(updated), created=\(created)")
        return (updated, created)
    }

    /// Create presence records for a newly created QSO
    private func createPresenceForNewQSO(_ qso: QSO, source: ServiceType) {
        for service in ServiceType.allCases {
            // POTA uploads only apply to QSOs where user was activating from a park
            let skipPOTAUpload = service == .pota && (qso.parkReference?.isEmpty ?? true)

            let presence =
                if service == source {
                    ServicePresence.downloaded(from: service, qso: qso)
                } else if service.supportsUpload, !skipPOTAUpload {
                    ServicePresence.needsUpload(to: service, qso: qso)
                } else {
                    ServicePresence(serviceType: service, isPresent: false, qso: qso)
                }
            modelContext.insert(presence)
            qso.servicePresence.append(presence)
        }
    }

    /// Merge multiple fetched QSOs into one (for new QSO creation)
    func mergeFetchedGroup(_ group: [FetchedQSO]) -> FetchedQSO {
        guard var merged = group.first else {
            fatalError("Empty group in mergeFetchedGroup")
        }

        for other in group.dropFirst() {
            merged = FetchedQSO(
                callsign: merged.callsign,
                band: merged.band,
                mode: merged.mode,
                frequency: merged.frequency ?? other.frequency,
                timestamp: merged.timestamp,
                rstSent: merged.rstSent.nonEmpty ?? other.rstSent,
                rstReceived: merged.rstReceived.nonEmpty ?? other.rstReceived,
                myCallsign: merged.myCallsign.isEmpty ? other.myCallsign : merged.myCallsign,
                myGrid: merged.myGrid.nonEmpty ?? other.myGrid,
                theirGrid: merged.theirGrid.nonEmpty ?? other.theirGrid,
                parkReference: FetchedQSO.combineParkReferences(merged.parkReference, other.parkReference),
                theirParkReference: merged.theirParkReference.nonEmpty ?? other.theirParkReference,
                notes: merged.notes.nonEmpty ?? other.notes,
                rawADIF: merged.rawADIF.nonEmpty ?? other.rawADIF,
                name: merged.name.nonEmpty ?? other.name,
                qth: merged.qth.nonEmpty ?? other.qth,
                state: merged.state.nonEmpty ?? other.state,
                country: merged.country.nonEmpty ?? other.country,
                power: merged.power ?? other.power,
                myRig: merged.myRig.nonEmpty ?? other.myRig,
                sotaRef: merged.sotaRef.nonEmpty ?? other.sotaRef,
                qrzLogId: merged.qrzLogId ?? other.qrzLogId,
                qrzConfirmed: merged.qrzConfirmed || other.qrzConfirmed,
                lotwConfirmedDate: merged.lotwConfirmedDate ?? other.lotwConfirmedDate,
                lotwConfirmed: merged.lotwConfirmed || other.lotwConfirmed,
                dxcc: merged.dxcc ?? other.dxcc,
                source: merged.source
            )
        }

        return merged
    }

    /// Create a QSO from merged fetched data
    func createQSO(from fetched: FetchedQSO) -> QSO {
        QSO(
            callsign: fetched.callsign,
            band: fetched.band,
            mode: fetched.mode,
            frequency: fetched.frequency,
            timestamp: fetched.timestamp,
            rstSent: fetched.rstSent,
            rstReceived: fetched.rstReceived,
            myCallsign: fetched.myCallsign,
            myGrid: fetched.myGrid,
            theirGrid: fetched.theirGrid,
            parkReference: fetched.parkReference,
            theirParkReference: fetched.theirParkReference,
            notes: fetched.notes,
            importSource: fetched.source.toImportSource,
            rawADIF: fetched.rawADIF,
            name: fetched.name,
            qth: fetched.qth,
            state: fetched.state,
            country: fetched.country,
            power: fetched.power,
            myRig: fetched.myRig,
            sotaRef: fetched.sotaRef,
            qrzLogId: fetched.qrzLogId,
            qrzConfirmed: fetched.qrzConfirmed,
            lotwConfirmedDate: fetched.lotwConfirmedDate,
            lotwConfirmed: fetched.lotwConfirmed,
            dxcc: fetched.dxcc
        )
    }
}
