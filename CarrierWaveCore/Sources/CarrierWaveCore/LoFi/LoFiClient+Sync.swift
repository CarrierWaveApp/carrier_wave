// swiftlint:disable function_body_length
import Foundation

// MARK: - Sync methods

public extension LoFiClient {
    /// Fetch all QSOs from all operations since last sync
    /// - Parameter onProgress: Optional callback invoked as QSOs are downloaded
    func fetchAllQsosSinceLastSync(
        onProgress: (@Sendable (SyncProgressInfo) -> Void)? = nil
    ) async throws -> LoFiDownloadResult {
        let lastSyncMillis = getLastSyncMillis()
        let isFreshSync = lastSyncMillis == 0

        logger.info("Starting LoFi sync")
        logger.info("Callsign: \(getCallsign() ?? "unknown")")

        if lastSyncMillis > 0 {
            let lastSyncDate = Date(timeIntervalSince1970: Double(lastSyncMillis) / 1_000.0)
            let formatter = ISO8601DateFormatter()
            logger.info("Last sync: \(formatter.string(from: lastSyncDate))")
        } else {
            logger.info("Last sync: Never (fresh sync)")
        }

        // Re-register to get fresh account info (including cutoff date)
        var hasCutoffDate = false
        do {
            let registration = try await register()
            logRegistrationDetails(registration)
            hasCutoffDate = registration.account.cutoffDateMillis != nil
        } catch {
            logger.warning(
                "Could not refresh registration: \(error.localizedDescription)"
            )
        }

        // Fetch account info for progress tracking
        var totalQSOs = 0
        var totalOperations = 0
        if let onProgress {
            do {
                let accountInfo = try await fetchAccountInfo()
                totalQSOs = accountInfo.qsos.syncable
                totalOperations = accountInfo.operations.syncable
                logger.info(
                    "Account has \(totalQSOs) syncable QSOs in \(totalOperations) operations"
                )
                onProgress(
                    SyncProgressInfo(
                        totalQSOs: totalQSOs,
                        totalOperations: totalOperations,
                        downloadedQSOs: 0,
                        processedOperations: 0
                    )
                )
            } catch {
                logger.warning(
                    "Could not fetch account info for progress: \(error.localizedDescription)"
                )
            }
        }

        // Fetch all operations (both active and deleted)
        let operations = try await fetchAllOperations(isFreshSync: isFreshSync)

        // Fetch QSOs for each operation with progress tracking
        let fetchResult = try await fetchQsosForOperations(
            operations,
            lastSyncMillis: lastSyncMillis,
            isFreshSync: isFreshSync,
            onProgress: onProgress.map { callback in
                { downloadedQSOs, processedOperations in
                    callback(
                        SyncProgressInfo(
                            totalQSOs: totalQSOs,
                            totalOperations: totalOperations,
                            downloadedQSOs: downloadedQSOs,
                            processedOperations: processedOperations
                        )
                    )
                }
            }
        )

        // Update last sync timestamp
        if fetchResult.maxSyncMillis > lastSyncMillis {
            try? credentials.setString(String(fetchResult.maxSyncMillis), for: .lastSyncMillis)
        }

        let allQsos = Array(fetchResult.qsosByUUID.values)

        // Log comprehensive summary
        logSyncSummary(
            operations: operations,
            qsos: allQsos,
            hasCutoffDate: hasCutoffDate
        )

        return LoFiDownloadResult(qsos: allQsos, rawFetchCount: fetchResult.rawFetchCount)
    }

    /// Fetch ALL QSOs from all operations (ignoring last sync timestamp, for force re-download)
    func fetchAllQsos() async throws -> LoFiDownloadResult {
        logger.info("Force re-downloading ALL QSOs")

        // Re-register to get fresh account info (including cutoff date)
        var hasCutoffDate = false
        do {
            let registration = try await register()
            logRegistrationDetails(registration)
            hasCutoffDate = registration.account.cutoffDateMillis != nil
        } catch {
            logger.warning(
                "Could not refresh registration: \(error.localizedDescription)"
            )
        }

        // Fetch all operations (treat as fresh sync to get everything)
        let operations = try await fetchAllOperations(isFreshSync: true)

        // Fetch all QSOs starting from 0
        let fetchResult = try await fetchQsosForOperations(
            operations,
            lastSyncMillis: 0,
            isFreshSync: true
        )

        let allQsos = Array(fetchResult.qsosByUUID.values)

        // Log comprehensive summary
        logSyncSummary(
            operations: operations,
            qsos: allQsos,
            hasCutoffDate: hasCutoffDate
        )

        return LoFiDownloadResult(qsos: allQsos, rawFetchCount: fetchResult.rawFetchCount)
    }
}

// MARK: - Internal sync helpers

extension LoFiClient {
    func fetchAllOperations(
        isFreshSync: Bool
    ) async throws -> [LoFiOperation] {
        var operationsByUUID: [String: LoFiOperation] = [:]

        logger.info("Fetching operations (fresh=\(isFreshSync))")

        for deleted in [false, true] {
            var syncedSince: Int64 = 0
            var pageCount = 0
            var totalFetched = 0

            while true {
                pageCount += 1
                let response = try await fetchOperations(
                    syncedSinceMillis: syncedSince,
                    otherClientsOnly: !isFreshSync,
                    deleted: deleted
                )

                totalFetched += response.operations.count
                for operation in response.operations {
                    operationsByUUID[operation.uuid] = operation
                }

                if response.meta.operations.recordsLeft == 0 {
                    break
                }
                guard
                    let next = response.meta.operations.nextUpdatedAtMillis
                    ?? response.meta.operations.nextSyncedAtMillis
                else {
                    logger.warning(
                        "recordsLeft=\(response.meta.operations.recordsLeft) but no nextUpdatedAtMillis"
                    )
                    break
                }
                syncedSince = Int64(next)
            }

            let opType = deleted ? "deleted" : "active"
            logger.info(
                "Fetched \(totalFetched) \(opType) operations in \(pageCount) pages"
            )
        }

        let operations = Array(operationsByUUID.values)
        let expectedQsos = operations.reduce(0) { $0 + $1.qsoCount }

        logger.info(
            "Total operations: \(operations.count), expected QSOs: \(expectedQsos)"
        )

        // Log date range of operations
        if !operations.isEmpty {
            let minMillis = operations.compactMap(\.startAtMillisMin).min() ?? 0
            let maxMillis = operations.compactMap(\.startAtMillisMax).max() ?? 0
            if minMillis > 0, maxMillis > 0 {
                let minDate = Date(timeIntervalSince1970: minMillis / 1_000.0)
                let maxDate = Date(timeIntervalSince1970: maxMillis / 1_000.0)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                logger.info(
                    "Operations span: \(formatter.string(from: minDate)) to \(formatter.string(from: maxDate))"
                )
            }
        }

        return operations
    }

    func fetchQsosForOperations(
        _ operations: [LoFiOperation],
        lastSyncMillis: Int64,
        isFreshSync: Bool,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> LoFiQsoFetchResult {
        let qsoSyncStart: Int64 = isFreshSync ? 0 : lastSyncMillis
        let totalOperations = operations.count
        let syncFlags = getSyncFlags()

        logger.info(
            "Fetching QSOs from \(totalOperations) operations with parallel downloads"
        )
        logger.info(
            "Using sync flags: batch=\(syncFlags.suggestedSyncBatchSize), delay=\(syncFlags.suggestedSyncLoopDelay)ms"
        )

        let accumulator = QSODownloadAccumulator(initialSyncMillis: lastSyncMillis)

        var operationIndex = 0
        while operationIndex < totalOperations {
            let concurrency = await accumulator.getConcurrency()
            let batchEnd = min(operationIndex + concurrency, totalOperations)
            let batch = Array(operations[operationIndex ..< batchEnd])

            await withTaskGroup(
                of: Result<([(LoFiQso, LoFiOperation)], Int64), Error>.self
            ) { group in
                for operation in batch {
                    group.addTask { [self] in
                        do {
                            let result = try await fetchQsosForOperation(
                                operation,
                                syncStart: qsoSyncStart,
                                isFreshSync: isFreshSync
                            )
                            return .success(result)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                for await result in group {
                    switch result {
                    case .success(let (qsos, syncMillis)):
                        await accumulator.addResults(qsos, syncMillis: syncMillis)
                    case let .failure(error):
                        await accumulator.recordError()
                        logger.warning(
                            "Operation fetch failed: \(error.localizedDescription)"
                        )
                    }
                }
            }

            let processedCount = await accumulator.getProcessedCount()
            let qsoCount = await accumulator.getQSOCount()

            if let onProgress {
                onProgress(qsoCount, processedCount)
            }

            let backoffDelay = await accumulator.getBackoffDelay()
            let loopDelayMs = syncFlags.suggestedSyncLoopDelay
            let delayMs = max(backoffDelay, UInt64(loopDelayMs))

            if operationIndex + batch.count < totalOperations, delayMs > 0 {
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }

            if operationIndex.isMultiple(of: 20) {
                await accumulator.increaseIfStable()
            }

            operationIndex = batchEnd
            await Task.yield()
        }

        let totalReceived = await accumulator.getTotalReceived()
        let (dict, syncMillis) = await accumulator.getResults()
        return LoFiQsoFetchResult(
            qsosByUUID: dict,
            maxSyncMillis: syncMillis,
            rawFetchCount: totalReceived
        )
    }

    func fetchQsosForOperation(
        _ operation: LoFiOperation,
        syncStart: Int64,
        isFreshSync: Bool
    ) async throws -> ([(LoFiQso, LoFiOperation)], Int64) {
        var qsos: [(LoFiQso, LoFiOperation)] = []
        var maxSyncMillis: Int64 = 0
        var qsoSyncedSince = syncStart

        // Note: LoFi QSO endpoint ignores the `deleted` param and always returns all QSOs
        // (both active and deleted), unlike the operations endpoint. No need to fetch twice.
        while true {
            let response = try await fetchOperationQsos(
                operationUUID: operation.uuid,
                syncedSinceMillis: qsoSyncedSince,
                otherClientsOnly: !isFreshSync
            )

            for qso in response.qsos {
                qsos.append((qso, operation))
                if let syncedAt = qso.syncedAtMillis {
                    maxSyncMillis = max(maxSyncMillis, Int64(syncedAt))
                }
            }

            if response.meta.qsos.recordsLeft == 0 {
                break
            }
            guard
                let next = response.meta.qsos.nextUpdatedAtMillis
                ?? response.meta.qsos.nextSyncedAtMillis
            else {
                logger.warning(
                    "Op \(operation.uuid): recordsLeft=\(response.meta.qsos.recordsLeft) but no next page"
                )
                break
            }
            qsoSyncedSince = Int64(next)
        }

        return (qsos, maxSyncMillis)
    }
}

// MARK: - Logging helpers

extension LoFiClient {
    func logRegistrationDetails(_ registration: LoFiRegistrationResponse) {
        logger.info("Account: \(registration.account.call)")

        if let cutoffDate = registration.account.cutoffDate {
            logger.warning(
                "CUTOFF DATE: \(cutoffDate) - older QSOs may not sync"
            )
        } else {
            logger.info("No cutoff date restriction")
        }

        if let cutoffMillis = registration.account.cutoffDateMillis {
            let date = Date(timeIntervalSince1970: Double(cutoffMillis) / 1_000.0)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            logger.warning("Cutoff: \(formatter.string(from: date))")
        }
    }

    func logSyncSummary(
        operations: [LoFiOperation],
        qsos: [(LoFiQso, LoFiOperation)],
        hasCutoffDate: Bool
    ) {
        logger.info("Total operations: \(operations.count)")

        let expectedQsoCount = operations.reduce(0) { $0 + $1.qsoCount }
        logger.info("Expected QSOs: \(expectedQsoCount), Actual: \(qsos.count)")

        if qsos.count != expectedQsoCount {
            let diff = expectedQsoCount - qsos.count
            if hasCutoffDate {
                logger.info(
                    "QSO count differs by \(diff) (expected due to cutoff date restriction)"
                )
            } else {
                logger.warning(
                    "QSO MISMATCH: expected \(expectedQsoCount), got \(qsos.count) (missing \(diff))"
                )
            }
        }

        if !qsos.isEmpty {
            let timestamps = qsos.compactMap(\.0.startAtMillis)
            let minTimestamp = timestamps.min() ?? 0
            let maxTimestamp = timestamps.max() ?? 0
            let minDate = Date(timeIntervalSince1970: minTimestamp / 1_000.0)
            let maxDate = Date(timeIntervalSince1970: maxTimestamp / 1_000.0)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            logger.info(
                "QSO date range: \(formatter.string(from: minDate)) to \(formatter.string(from: maxDate))"
            )
        }

        var mismatchCount = 0
        for op in operations {
            let opQsos = qsos.filter { $0.1.uuid == op.uuid }
            if opQsos.count != op.qsoCount {
                mismatchCount += 1
            }
        }
        if mismatchCount > 0, !hasCutoffDate {
            logger.warning(
                "\(mismatchCount) operations have QSO count mismatches"
            )
        }
    }
}

// swiftlint:enable function_body_length
