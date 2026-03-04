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
        let qrzHasKey: Bool
        let potaIsConfigured: Bool
        let potaInMaintenance: Bool
        let lofiReady: Bool
        let hamrsReady: Bool
        let lotwHasCreds: Bool
        let clublogReady: Bool
    }

    private func captureServiceConfiguration() -> ServiceConfiguration {
        // Capture service configuration state before entering task group
        ServiceConfiguration(
            qrzHasKey: qrzClient.hasApiKey(),
            // Use isConfigured (has stored credentials) instead of isAuthenticated (has valid token)
            // This allows POTA sync to proceed even if token expired - ensureValidToken will re-auth
            potaIsConfigured: potaAuthService.isConfigured,
            potaInMaintenance: POTAClient.isInMaintenanceWindow(),
            lofiReady: lofiClient.isConfigured && lofiClient.isLinked,
            hamrsReady: hamrsClient.isConfigured,
            lotwHasCreds: lotwClient.hasCredentials(),
            clublogReady: clublogClient.isConfigured
        )
    }

    private func addDownloadTasks(
        to group: inout TaskGroup<(ServiceType, Result<[FetchedQSO], Error>)>,
        config: ServiceConfiguration,
        timeout: TimeInterval,
        extendedTimeout: TimeInterval
    ) {
        if config.qrzHasKey {
            group.addTask { await self.downloadFromQRZ(timeout: timeout) }
        }
        // POTA: skip during maintenance window, uses extended timeout
        if config.potaIsConfigured, !config.potaInMaintenance {
            group.addTask { await self.downloadFromPOTA(timeout: extendedTimeout) }
        }
        if config.lofiReady {
            group.addTask { await self.downloadFromLoFi(timeout: timeout) }
        }
        if config.hamrsReady {
            group.addTask { await self.downloadFromHAMRS(timeout: timeout) }
        }
        // LoTW: uses extended timeout for adaptive windowing
        if config.lotwHasCreds {
            group.addTask { await self.downloadFromLoTW(timeout: extendedTimeout) }
        }
        if config.clublogReady {
            group.addTask { await self.downloadFromClubLog(timeout: timeout) }
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

        // Use incremental sync if we have a last download date
        let lastDownload = qrzClient.getLastDownloadDate()
        let syncStartTime = Date()

        if let lastDownload {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.info(
                "Starting incremental QRZ download (since \(formatter.string(from: lastDownload)))",
                service: .qrz
            )
        } else {
            debugLog.info("Starting full QRZ download (no previous sync)", service: .qrz)
        }

        do {
            let qsos = try await withTimeout(seconds: timeout, service: .qrz) {
                try await self.qrzClient.fetchQSOs(since: lastDownload)
            }
            debugLog.info("Downloaded \(qsos.count) QSOs from QRZ", service: .qrz)
            let fetched = qsos.map { FetchedQSO.fromQRZ($0) }
            for (index, qso) in qsos.prefix(5).enumerated() {
                debugLog.logRawQSO(
                    service: .qrz,
                    rawJSON: qso.rawADIF,
                    parsedFields: fetched[index].debugFields
                )
            }

            // Save sync timestamp on success
            qrzClient.saveLastDownloadDate(syncStartTime)

            await MainActor.run {
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
            let (qsos, remoteMap) = try await withTimeout(seconds: timeout, service: .pota) {
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
            potaRemoteQSOMap = remoteMap
            let fetched = qsos.map { FetchedQSO.fromPOTA($0) }
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
        try await withTimeout(seconds: timeout, service: .lofi) {
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

    private func downloadFromHAMRS(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run {
            self.syncPhase = .downloading(service: .hamrs)
            self.serviceSyncStates[.hamrs] = .downloading
        }
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting HAMRS download", service: .hamrs)
        do {
            let qsos = try await withTimeout(seconds: timeout, service: .hamrs) {
                try await self.hamrsClient.fetchAllQSOs()
            }
            debugLog.info("Downloaded \(qsos.count) raw QSOs from HAMRS", service: .hamrs)
            let fetchedList = qsos.compactMap { FetchedQSO.fromHAMRS($0.0, logbook: $0.1) }
            debugLog.info(
                "After filtering: \(fetchedList.count) valid, \(qsos.count - fetchedList.count) skipped",
                service: .hamrs
            )
            await MainActor.run {
                self.syncProgress.addDownloaded(fetchedList.count, for: .hamrs)
                self.serviceSyncStates[.hamrs] = .downloaded(count: fetchedList.count)
            }
            return (.hamrs, .success(fetchedList))
        } catch HAMRSError.subscriptionInactive {
            debugLog.warning("HAMRS subscription inactive - skipping download", service: .hamrs)
            await MainActor.run {
                self.serviceSyncStates[.hamrs] = .downloaded(count: 0)
            }
            return (.hamrs, .success([]))
        } catch {
            debugLog.error("HAMRS download failed: \(error.localizedDescription)", service: .hamrs)
            await MainActor.run {
                self.serviceSyncStates[.hamrs] = .error(error.localizedDescription)
            }
            return (.hamrs, .failure(error))
        }
    }

    private func fetchLoTWCallsigns(debugLog: SyncDebugLog) async -> [String] {
        let userCallsigns = await MainActor.run {
            Array(CallsignAliasService.shared.getAllUserCallsigns())
        }
        if userCallsigns.isEmpty {
            debugLog.warning(
                "No callsigns configured - fetching all QSOs for LoTW account", service: .lotw
            )
        } else {
            debugLog.info(
                "Fetching QSOs for callsigns: \(userCallsigns.joined(separator: ", "))",
                service: .lotw
            )
        }
        return userCallsigns
    }

    private func downloadFromLoTW(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run {
            self.syncPhase = .downloading(service: .lotw)
            self.serviceSyncStates[.lotw] = .downloading
        }
        let debugLog = SyncDebugLog.shared
        let rxSince = lotwClient.getLastQSORxDate()
        debugLog.info("Starting LoTW download", service: .lotw)

        let userCallsigns = await fetchLoTWCallsigns(debugLog: debugLog)

        do {
            let response = try await withTimeout(seconds: timeout, service: .lotw) {
                try await self.lotwClient.fetchQSOs(
                    forCallsigns: userCallsigns, qsoRxSince: rxSince
                )
            }
            debugLog.info("Downloaded \(response.qsos.count) QSOs from LoTW", service: .lotw)

            let fetched = response.qsos.map { FetchedQSO.fromLoTW($0) }

            // Save timestamp for incremental sync
            if let lastQSORx = response.lastQSORx {
                try lotwClient.saveLastQSORxDate(lastQSORx)
            }

            for (index, qso) in response.qsos.prefix(5).enumerated() {
                debugLog.logRawQSO(
                    service: .lotw,
                    rawJSON: qso.rawADIF,
                    parsedFields: fetched[index].debugFields
                )
            }
            await MainActor.run {
                self.syncProgress.addDownloaded(fetched.count, for: .lotw)
                self.serviceSyncStates[.lotw] = .downloaded(count: fetched.count)
            }
            return (.lotw, .success(fetched))
        } catch {
            debugLog.error("LoTW download failed: \(error.localizedDescription)", service: .lotw)
            await MainActor.run {
                self.serviceSyncStates[.lotw] = .error(error.localizedDescription)
            }
            return (.lotw, .failure(error))
        }
    }

    private func downloadFromClubLog(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run {
            self.syncPhase = .downloading(service: .clublog)
            self.serviceSyncStates[.clublog] = .downloading
        }
        let debugLog = SyncDebugLog.shared

        let lastDownload = clublogClient.getLastDownloadDate()
        let syncStartTime = Date()

        if let lastDownload {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.info(
                "Starting incremental Club Log download "
                    + "(since \(formatter.string(from: lastDownload)))",
                service: .clublog
            )
        } else {
            debugLog.info(
                "Starting full Club Log download (no previous sync)", service: .clublog
            )
        }

        do {
            let qsos = try await withTimeout(seconds: timeout, service: .clublog) {
                try await self.clublogClient.fetchQSOs(since: lastDownload)
            }
            debugLog.info(
                "Downloaded \(qsos.count) QSOs from Club Log", service: .clublog
            )
            let fetched = qsos.map { FetchedQSO.fromClubLog($0) }

            // Save sync timestamp on success
            clublogClient.saveLastDownloadDate(syncStartTime)

            await MainActor.run {
                self.syncProgress.addDownloaded(fetched.count, for: .clublog)
                self.serviceSyncStates[.clublog] = .downloaded(count: fetched.count)
            }
            return (.clublog, .success(fetched))
        } catch {
            debugLog.error(
                "Club Log download failed: \(error.localizedDescription)",
                service: .clublog
            )
            await MainActor.run {
                self.serviceSyncStates[.clublog] = .error(error.localizedDescription)
            }
            return (.clublog, .failure(error))
        }
    }
}
