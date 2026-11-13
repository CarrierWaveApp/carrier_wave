import CarrierWaveData
import Foundation
import SwiftData

// MARK: - SyncService Download Methods

extension SyncService {
    func downloadFromAllSources() async -> [ServiceType: Result<[FetchedQSO], Error>] {
        let timeout = syncTimeoutSeconds
        let extendedTimeout = extendedSyncTimeoutSeconds
        let serviceConfig = captureServiceConfiguration()

        typealias DownloadResult = (ServiceType, Result<[FetchedQSO], any Error>)
        return await withTaskGroup(of: DownloadResult.self) { group in
            addDownloadTasks(
                to: &group, config: serviceConfig,
                timeout: timeout, extendedTimeout: extendedTimeout
            )

            var results: [ServiceType: Result<[FetchedQSO], Error>] = [:]
            for await (service, result) in group {
                results[service] = result
            }
            return results
        }
    }

    private struct ServiceConfiguration {
        let qrzHasMappings: Bool
        let potaIsConfigured: Bool
        let potaInMaintenance: Bool
        let lofiReady: Bool
        let hamrsReady: Bool
        let lotwHasCreds: Bool
        let clublogReady: Bool
        let eqslReady: Bool
    }

    private func captureServiceConfiguration() -> ServiceConfiguration {
        // Capture service configuration state before entering task group
        ServiceConfiguration(
            qrzHasMappings: !qrzClient.getCallsignMappings().isEmpty,
            // Use isConfigured (has stored credentials) instead of isAuthenticated (has valid token)
            // This allows POTA sync to proceed even if token expired - ensureValidToken will re-auth
            potaIsConfigured: potaAuthService.isConfigured,
            potaInMaintenance: POTAClient.isInMaintenanceWindow(),
            lofiReady: lofiClient.isConfigured && lofiClient.isLinked,
            hamrsReady: hamrsClient.isConfigured,
            lotwHasCreds: lotwClient.hasCredentials(),
            clublogReady: clublogClient.isConfigured,
            eqslReady: eqslClient.isConfigured
        )
    }

    private func addDownloadTasks(
        to group: inout TaskGroup<(ServiceType, Result<[FetchedQSO], Error>)>,
        config: ServiceConfiguration,
        timeout: TimeInterval,
        extendedTimeout: TimeInterval
    ) {
        let debugLog = SyncDebugLog.shared
        if config.qrzHasMappings, isDownloadEnabled(for: .qrz) {
            group.addTask { await self.downloadFromQRZ(timeout: timeout) }
        } else if config.qrzHasMappings {
            debugLog.debug("QRZ download skipped: upload-only mode", service: .qrz)
        } else {
            debugLog.debug("QRZ download skipped: no callsign mappings configured", service: .qrz)
        }
        // POTA: skip during maintenance window, uses extended timeout
        if config.potaIsConfigured, !config.potaInMaintenance, isDownloadEnabled(for: .pota) {
            group.addTask { await self.downloadFromPOTA(timeout: extendedTimeout) }
        }
        if config.lofiReady, isDownloadEnabled(for: .lofi) {
            group.addTask { await self.downloadFromLoFi(timeout: timeout) }
        }
        if config.hamrsReady, isDownloadEnabled(for: .hamrs) {
            group.addTask { await self.downloadFromHAMRS(timeout: timeout) }
        }
        // LoTW: uses extended timeout for adaptive windowing
        if config.lotwHasCreds, isDownloadEnabled(for: .lotw) {
            group.addTask { await self.downloadFromLoTW(timeout: extendedTimeout) }
        }
        // Club Log: "Coming Soon" — not yet configurable as a sync source
        if config.eqslReady, isDownloadEnabled(for: .eqsl) {
            group.addTask { await self.downloadFromEQSL(timeout: timeout) }
        }
    }

    private func downloadFromQRZ(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run {
            self.syncPhase = .downloading(service: .qrz)
            self.serviceSyncStates[.qrz] = .downloading
        }
        let debugLog = SyncDebugLog.shared
        let mappings = qrzClient.getCallsignMappings()
        let lastDownload = qrzClient.getLastDownloadDate()

        logQRZDownloadStart(lastDownload: lastDownload, accountCount: mappings.count)

        do {
            let allQSOs = try await fetchQSOsFromAllMappings(
                mappings, since: lastDownload, timeout: timeout
            )
            let fetched = allQSOs.map { FetchedQSO.fromQRZ($0) }

            for (index, qso) in allQSOs.prefix(5).enumerated() {
                debugLog.logRawQSO(
                    service: .qrz,
                    rawJSON: qso.rawADIF,
                    parsedFields: fetched[index].debugFields
                )
            }

            let confirmedLogIds = await fetchQRZConfirmedLogIds(timeout: timeout)
            qrzClient.saveLastDownloadDate(Date())

            await MainActor.run {
                self.qrzConfirmedLogIds = confirmedLogIds
                self.syncProgress.addDownloaded(fetched.count, for: .qrz)
                self.serviceSyncStates[.qrz] = .downloaded(count: fetched.count)
            }
            return (.qrz, .success(fetched))
        } catch {
            debugLog.error("QRZ download failed: \(error.localizedDescription)", service: .qrz)
            await MainActor.run {
                self.serviceSyncStates[.qrz] = .error(error.localizedDescription)
            }
            return (.qrz, .failure(error))
        }
    }

    /// Fetch QSOs from all configured QRZ API key mappings.
    func fetchQSOsFromAllMappings(
        _ mappings: [QRZCallsignMapping], since: Date?, timeout: TimeInterval
    ) async throws -> [QRZFetchedQSO] {
        let debugLog = SyncDebugLog.shared
        var allQSOs: [QRZFetchedQSO] = []

        for mapping in mappings {
            let qsos = try await withTimeout(seconds: timeout, service: .qrz) {
                try await self.qrzClient.fetchQSOs(
                    apiKey: mapping.apiKey, since: since
                )
            }
            debugLog.info(
                "Downloaded \(qsos.count) QSOs from QRZ (\(mapping.callsign))",
                service: .qrz
            )
            allQSOs.append(contentsOf: qsos)
        }

        return allQSOs
    }

    private func logQRZDownloadStart(lastDownload: Date?, accountCount: Int) {
        let debugLog = SyncDebugLog.shared
        if let lastDownload {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.info(
                "Starting incremental QRZ download (since \(formatter.string(from: lastDownload)))"
                    + " from \(accountCount) account(s)",
                service: .qrz
            )
        } else {
            debugLog.info(
                "Starting full QRZ download from \(accountCount) account(s)",
                service: .qrz
            )
        }
    }

    /// Fetch confirmed QRZ log IDs using TYPE:LOGIDS. Non-fatal — returns empty on failure.
    /// Much lighter than fetching full ADIF for every confirmed QSO.
    func fetchQRZConfirmedLogIds(timeout: TimeInterval) async -> Set<String> {
        let debugLog = SyncDebugLog.shared
        do {
            let ids = try await withTimeout(seconds: timeout, service: .qrz) {
                try await self.qrzClient.fetchConfirmedLogIds()
            }
            if !ids.isEmpty {
                debugLog.info("Fetched \(ids.count) confirmed log IDs from QRZ", service: .qrz)
            }
            return ids
        } catch {
            debugLog.warning(
                "QRZ confirmed log IDs fetch failed (non-fatal): \(error.localizedDescription)",
                service: .qrz
            )
            return []
        }
    }

    private func logPOTASyncState(debugLog: SyncDebugLog) {
        if let syncState = potaClient.loadSyncState() {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.info(
                "Starting incremental POTA download "
                    + "(since \(formatter.string(from: syncState.lastSyncDate)))",
                service: .pota
            )
        } else {
            debugLog.info("Starting full POTA download (no previous sync)", service: .pota)
        }
    }

    private func downloadFromPOTA(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run {
            self.syncPhase = .downloading(service: .pota)
            self.serviceSyncStates[.pota] = .downloading
        }
        let debugLog = SyncDebugLog.shared
        logPOTASyncState(debugLog: debugLog)

        do {
            let output = try await withTimeout(seconds: timeout, service: .pota) { [self] in
                try await self.potaClient.fetchAllQSOs { [weak self] processed, total, phase, qsoCount in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            return
                        }
                        var updated = syncProgress
                        updated.potaProcessedActivations = processed
                        updated.potaTotalActivations = total
                        updated.potaPhase = phase
                        updated.potaDownloadedQSOs = qsoCount
                        syncProgress = updated
                    }
                }
            }
            potaRemoteQSOMap = output.remoteQSOMap
            potaActivationSnapshots = output.activationSnapshots
            let fetched = output.qsos.map { FetchedQSO.fromPOTA($0) }
            debugLog.info("Downloaded \(fetched.count) QSOs from POTA", service: .pota)
            await MainActor.run {
                self.syncProgress.addDownloaded(fetched.count, for: .pota)
                self.serviceSyncStates[.pota] = .downloaded(count: fetched.count)
            }
            return (.pota, .success(fetched))
        } catch {
            debugLog.error("POTA download failed: \(error.localizedDescription)", service: .pota)
            await MainActor.run {
                self.serviceSyncStates[.pota] = .error(error.localizedDescription)
            }
            return (.pota, .failure(error))
        }
    }

    private func downloadFromLoFi(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run {
            self.syncPhase = .downloading(service: .lofi)
            self.serviceSyncStates[.lofi] = .downloading
        }
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting LoFi download", service: .lofi)
        logLoFiSyncState(debugLog: debugLog)

        do {
            let downloadResult = try await fetchLoFiQSOs(timeout: timeout)
            let qsos = downloadResult.qsos
            debugLog.info(
                "Downloaded \(downloadResult.rawFetchCount) raw QSOs from LoFi API (\(qsos.count) after dedup)",
                service: .lofi
            )
            logQSODateRange(qsos: qsos, debugLog: debugLog)

            let (fetchedList, skippedCount) = await convertLoFiQSOsWithYielding(qsos)
            debugLog.info(
                "After filtering: \(fetchedList.count) valid, \(skippedCount) skipped",
                service: .lofi
            )
            logLoFiSampleQSOs(qsos: qsos, fetched: fetchedList, debugLog: debugLog)
            await MainActor.run {
                self.syncProgress.addDownloaded(fetchedList.count, for: .lofi)
                self.serviceSyncStates[.lofi] = .downloaded(count: fetchedList.count)
            }
            return (.lofi, .success(fetchedList))
        } catch {
            debugLog.error("LoFi download failed: \(error.localizedDescription)", service: .lofi)
            await MainActor.run {
                self.serviceSyncStates[.lofi] = .error(error.localizedDescription)
            }
            return (.lofi, .failure(error))
        }
    }

    private func logLoFiSyncState(debugLog: SyncDebugLog) {
        let lastSyncMillis = lofiClient.getLastSyncMillis()
        if lastSyncMillis > 0 {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let lastSyncDate = Date(timeIntervalSince1970: Double(lastSyncMillis) / 1_000.0)
            debugLog.info("Last sync: \(formatter.string(from: lastSyncDate))", service: .lofi)
        } else {
            debugLog.info("Last sync: Never (fresh sync)", service: .lofi)
        }
    }

    private func fetchLoFiQSOs(timeout: TimeInterval) async throws -> LoFiDownloadResult {
        try await withTimeout(seconds: timeout, service: .lofi) { [self] in
            try await self.lofiClient.fetchAllQsosSinceLastSync { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    NSLog("[LoFi Progress] total=%d, downloaded=%d", progress.totalQSOs, progress.downloadedQSOs)
                    var updated = syncProgress
                    updated.lofiTotalQSOs = progress.totalQSOs
                    updated.lofiTotalOperations = progress.totalOperations
                    updated.lofiDownloadedQSOs = progress.downloadedQSOs
                    syncProgress = updated
                }
            }
        }
    }

    private func logQSODateRange(qsos: [(LoFiQso, LoFiOperation)], debugLog: SyncDebugLog) {
        guard !qsos.isEmpty else {
            return
        }
        let timestamps = qsos.compactMap(\.0.startAtMillis)
        guard let minTs = timestamps.min(), let maxTs = timestamps.max() else {
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let minDate = formatter.string(from: Date(timeIntervalSince1970: minTs / 1_000.0))
        let maxDate = formatter.string(from: Date(timeIntervalSince1970: maxTs / 1_000.0))
        debugLog.info("QSO date range: \(minDate) to \(maxDate)", service: .lofi)
    }

    /// Convert LoFi QSOs to FetchedQSO format with periodic yields to avoid blocking UI
    private func convertLoFiQSOsWithYielding(
        _ qsos: [(LoFiQso, LoFiOperation)]
    ) async -> ([FetchedQSO], Int) {
        var skippedCount = 0
        var fetchedList: [FetchedQSO] = []
        fetchedList.reserveCapacity(qsos.count)

        for (index, (lofiQso, operation)) in qsos.enumerated() {
            if let fetched = FetchedQSO.fromLoFi(lofiQso, operation: operation) {
                fetchedList.append(fetched)
            } else {
                skippedCount += 1
            }

            // Yield periodically to allow UI updates and other tasks to run
            if index.isMultiple(of: 500) {
                await Task.yield()
            }
        }

        return (fetchedList, skippedCount)
    }

    private func logLoFiSampleQSOs(
        qsos: [(LoFiQso, LoFiOperation)],
        fetched: [FetchedQSO],
        debugLog: SyncDebugLog
    ) {
        for (index, (lofiQso, op)) in qsos.prefix(5).enumerated() {
            let rawJSON = """
            {
              "uuid": "\(lofiQso.uuid)",
              "startAtMillis": \(lofiQso.startAtMillis.map { String($0) } ?? "nil"),
              "band": "\(lofiQso.band ?? "nil")",
              "mode": "\(lofiQso.mode ?? "nil")",
              "freq": \(lofiQso.freq.map { String($0) } ?? "nil"),
              "their": { "call": "\(lofiQso.their?.call ?? "nil")" },
              "operation": "\(op.uuid)"
            }
            """
            if index < fetched.count {
                debugLog.logRawQSO(
                    service: .lofi,
                    rawJSON: rawJSON,
                    parsedFields: fetched[index].debugFields
                )
            }
        }
    }
}
