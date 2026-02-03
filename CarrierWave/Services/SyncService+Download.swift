// swiftlint:disable function_body_length
import Foundation
import SwiftData

// MARK: - SyncService Download Methods

extension SyncService {
    func downloadFromAllSources() async -> [ServiceType: Result<[FetchedQSO], Error>] {
        let timeout = syncTimeoutSeconds
        let extendedTimeout = extendedSyncTimeoutSeconds

        // Capture service configuration state before entering task group
        let qrzHasKey = qrzClient.hasApiKey()
        let potaIsAuth = potaAuthService.isAuthenticated
        let potaInMaintenance = POTAClient.isInMaintenanceWindow()
        let lofiReady = lofiClient.isConfigured && lofiClient.isLinked
        let hamrsReady = hamrsClient.isConfigured
        let lotwHasCreds = lotwClient.hasCredentials()

        return await withTaskGroup(of: (ServiceType, Result<[FetchedQSO], Error>).self) { group in
            // QRZ download
            if qrzHasKey {
                group.addTask {
                    await self.downloadFromQRZ(timeout: timeout)
                }
            }

            // POTA download (skip during maintenance window)
            // Uses extended timeout - POTA handles its own per-activation timeouts
            if potaIsAuth, !potaInMaintenance {
                group.addTask {
                    await self.downloadFromPOTA(timeout: extendedTimeout)
                }
            }

            // LoFi download
            if lofiReady {
                group.addTask {
                    await self.downloadFromLoFi(timeout: timeout)
                }
            }

            // HAMRS download
            if hamrsReady {
                group.addTask {
                    await self.downloadFromHAMRS(timeout: timeout)
                }
            }

            // LoTW download
            // Uses extended timeout - LoTW handles its own adaptive windowing
            if lotwHasCreds {
                group.addTask {
                    await self.downloadFromLoTW(timeout: extendedTimeout)
                }
            }

            var results: [ServiceType: Result<[FetchedQSO], Error>] = [:]
            for await (service, result) in group {
                results[service] = result
            }
            return results
        }
    }

    private func downloadFromQRZ(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run { self.syncPhase = .downloading(service: .qrz) }
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

            await MainActor.run { self.syncProgress.addDownloaded(fetched.count, for: .qrz) }
            return (.qrz, .success(fetched))
        } catch {
            debugLog.error("QRZ download failed: \(error.localizedDescription)", service: .qrz)
            return (.qrz, .failure(error))
        }
    }

    private func downloadFromPOTA(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run { self.syncPhase = .downloading(service: .pota) }
        let debugLog = SyncDebugLog.shared

        // Log incremental sync status
        if let syncState = potaClient.loadSyncState() {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.info(
                "Starting incremental POTA download (since \(formatter.string(from: syncState.lastSyncDate)))",
                service: .pota
            )
        } else {
            debugLog.info("Starting full POTA download (no previous sync)", service: .pota)
        }

        do {
            let qsos = try await withTimeout(seconds: timeout, service: .pota) {
                try await self.potaClient.fetchAllQSOs()
            }
            debugLog.info("Downloaded \(qsos.count) QSOs from POTA", service: .pota)
            let fetched = qsos.map { FetchedQSO.fromPOTA($0) }
            for (index, qso) in fetched.prefix(5).enumerated() {
                debugLog.logRawQSO(
                    service: .pota,
                    rawJSON: "POTA QSO: \(qsos[index].callsign) @ \(qsos[index].timestamp)",
                    parsedFields: qso.debugFields
                )
            }
            await MainActor.run { self.syncProgress.addDownloaded(fetched.count, for: .pota) }
            return (.pota, .success(fetched))
        } catch {
            debugLog.error("POTA download failed: \(error.localizedDescription)", service: .pota)
            return (.pota, .failure(error))
        }
    }

    private func downloadFromLoFi(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run { self.syncPhase = .downloading(service: .lofi) }
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting LoFi download", service: .lofi)

        // Log LoFi configuration state
        let lastSyncMillis = lofiClient.getLastSyncMillis()
        if lastSyncMillis > 0 {
            let lastSyncDate = Date(timeIntervalSince1970: Double(lastSyncMillis) / 1_000.0)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.info("Last sync: \(formatter.string(from: lastSyncDate))", service: .lofi)
        } else {
            debugLog.info("Last sync: Never (fresh sync)", service: .lofi)
        }

        do {
            let qsos = try await withTimeout(seconds: timeout, service: .lofi) {
                try await self.lofiClient.fetchAllQsosSinceLastSync { [weak self] progress in
                    guard let self else {
                        return
                    }
                    // Update progress - must modify struct to trigger @Published
                    NSLog(
                        "[LoFi Progress] total=%d, downloaded=%d",
                        progress.totalQSOs, progress.downloadedQSOs
                    )
                    var updated = syncProgress
                    updated.lofiTotalQSOs = progress.totalQSOs
                    updated.lofiTotalOperations = progress.totalOperations
                    updated.lofiDownloadedQSOs = progress.downloadedQSOs
                    syncProgress = updated
                }
            }
            debugLog.info("Downloaded \(qsos.count) raw QSOs from LoFi API", service: .lofi)

            // Log date range of downloaded QSOs
            if !qsos.isEmpty {
                let timestamps = qsos.compactMap(\.0.startAtMillis)
                let minTimestamp = timestamps.min() ?? 0
                let maxTimestamp = timestamps.max() ?? 0
                let minDate = Date(timeIntervalSince1970: minTimestamp / 1_000.0)
                let maxDate = Date(timeIntervalSince1970: maxTimestamp / 1_000.0)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                debugLog.info(
                    "QSO date range: \(formatter.string(from: minDate)) to \(formatter.string(from: maxDate))",
                    service: .lofi
                )
            }

            // Convert to FetchedQSO with periodic yields to avoid blocking UI
            let (fetchedList, skippedCount) = await convertLoFiQSOsWithYielding(qsos)

            debugLog.info(
                "After filtering: \(fetchedList.count) valid, \(skippedCount) skipped",
                service: .lofi
            )
            logLoFiSampleQSOs(qsos: qsos, fetched: fetchedList, debugLog: debugLog)
            await MainActor.run { self.syncProgress.addDownloaded(fetchedList.count, for: .lofi) }
            return (.lofi, .success(fetchedList))
        } catch {
            debugLog.error("LoFi download failed: \(error.localizedDescription)", service: .lofi)
            return (.lofi, .failure(error))
        }
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
        await MainActor.run { self.syncPhase = .downloading(service: .hamrs) }
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting HAMRS download", service: .hamrs)
        do {
            let qsos = try await withTimeout(seconds: timeout, service: .hamrs) {
                try await self.hamrsClient.fetchAllQSOs()
            }
            debugLog.info("Downloaded \(qsos.count) raw QSOs from HAMRS", service: .hamrs)

            var skippedCount = 0
            var fetchedList: [FetchedQSO] = []
            for (hamrsQso, logbook) in qsos {
                if let fetched = FetchedQSO.fromHAMRS(hamrsQso, logbook: logbook) {
                    fetchedList.append(fetched)
                } else {
                    skippedCount += 1
                    debugLog.warning(
                        """
                        Skipped QSO: call=\(hamrsQso.call ?? "nil"), \
                        band=\(hamrsQso.band ?? "nil"), mode=\(hamrsQso.mode ?? "nil")
                        """,
                        service: .hamrs
                    )
                }
            }
            debugLog.info(
                "After filtering: \(fetchedList.count) valid, \(skippedCount) skipped",
                service: .hamrs
            )

            for fetched in fetchedList.prefix(5) {
                debugLog.logRawQSO(
                    service: .hamrs,
                    rawJSON: "HAMRS QSO: \(fetched.callsign) @ \(fetched.timestamp)",
                    parsedFields: fetched.debugFields
                )
            }
            await MainActor.run { self.syncProgress.addDownloaded(fetchedList.count, for: .hamrs) }
            return (.hamrs, .success(fetchedList))
        } catch HAMRSError.subscriptionInactive {
            debugLog.warning("HAMRS subscription inactive - skipping download", service: .hamrs)
            return (.hamrs, .success([]))
        } catch {
            debugLog.error("HAMRS download failed: \(error.localizedDescription)", service: .hamrs)
            return (.hamrs, .failure(error))
        }
    }

    private func downloadFromLoTW(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run { self.syncPhase = .downloading(service: .lotw) }
        let debugLog = SyncDebugLog.shared
        let rxSince = lotwClient.getLastQSORxDate()
        debugLog.info("Starting LoTW download", service: .lotw)
        do {
            let response = try await withTimeout(seconds: timeout, service: .lotw) {
                try await self.lotwClient.fetchQSOs(qsoRxSince: rxSince)
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
            await MainActor.run { self.syncProgress.addDownloaded(fetched.count, for: .lotw) }
            return (.lotw, .success(fetched))
        } catch {
            debugLog.error("LoTW download failed: \(error.localizedDescription)", service: .lotw)
            return (.lotw, .failure(error))
        }
    }

    // MARK: - Force Re-download Methods

    /// Force re-download all QSOs from QRZ and reprocess them
    func forceRedownloadFromQRZ() async throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Force re-downloading from QRZ", service: .qrz)

        let qsos = try await qrzClient.fetchQSOs(since: nil)
        let fetched = qsos.map { FetchedQSO.fromQRZ($0) }

        debugLog.info("Fetched \(fetched.count) QSOs from QRZ", service: .qrz)
        return try reprocessQSOs(fetched)
    }

    /// Force re-download all QSOs from POTA and reprocess them
    func forceRedownloadFromPOTA() async throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Force re-downloading from POTA", service: .pota)

        // Clear both checkpoint and persistent sync state to ensure full re-download
        potaClient.clearDownloadCheckpoint()
        potaClient.clearSyncState()

        let qsos = try await potaClient.fetchAllQSOs()
        let fetched = qsos.map { FetchedQSO.fromPOTA($0) }

        debugLog.info("Fetched \(fetched.count) QSOs from POTA", service: .pota)
        return try reprocessQSOs(fetched)
    }

    /// Force re-download all QSOs from LoFi and reprocess them
    func forceRedownloadFromLoFi() async throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Force re-downloading from LoFi", service: .lofi)

        // Log current state before re-download
        let lastSyncMillis = lofiClient.getLastSyncMillis()
        if lastSyncMillis > 0 {
            let lastSyncDate = Date(timeIntervalSince1970: Double(lastSyncMillis) / 1_000.0)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.info(
                "Previous last sync: \(formatter.string(from: lastSyncDate))", service: .lofi
            )
        }
        debugLog.info("Ignoring last sync timestamp, fetching ALL QSOs", service: .lofi)

        // Fetch ALL QSOs, not just since last sync
        let qsos = try await lofiClient.fetchAllQsos()

        // Log date range
        if !qsos.isEmpty {
            let timestamps = qsos.compactMap(\.0.startAtMillis)
            let minTimestamp = timestamps.min() ?? 0
            let maxTimestamp = timestamps.max() ?? 0
            let minDate = Date(timeIntervalSince1970: minTimestamp / 1_000.0)
            let maxDate = Date(timeIntervalSince1970: maxTimestamp / 1_000.0)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            debugLog.info(
                "QSO date range: \(formatter.string(from: minDate)) to \(formatter.string(from: maxDate))",
                service: .lofi
            )
        }

        let fetched = qsos.compactMap { FetchedQSO.fromLoFi($0.0, operation: $0.1) }

        debugLog.info("Fetched \(fetched.count) QSOs from LoFi", service: .lofi)
        return try reprocessQSOs(fetched)
    }

    /// Force re-download all QSOs from HAMRS and reprocess them
    func forceRedownloadFromHAMRS() async throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Force re-downloading from HAMRS", service: .hamrs)

        let qsos = try await hamrsClient.fetchAllQSOs()
        let fetched = qsos.compactMap { FetchedQSO.fromHAMRS($0.0, logbook: $0.1) }

        debugLog.info("Fetched \(fetched.count) QSOs from HAMRS", service: .hamrs)
        return try reprocessQSOs(fetched)
    }

    /// Force re-download all QSOs from LoTW and reprocess them
    func forceRedownloadFromLoTW() async throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Force re-downloading from LoTW", service: .lotw)

        // Fetch ALL QSOs (no qsoRxSince filter)
        let response = try await lotwClient.fetchQSOs(qsoRxSince: nil)
        let fetched = response.qsos.map { FetchedQSO.fromLoTW($0) }

        debugLog.info("Fetched \(fetched.count) QSOs from LoTW", service: .lotw)
        return try reprocessQSOs(fetched)
    }
}
