import CarrierWaveData
import Foundation
import SwiftData

// MARK: - SyncService Individual Download Methods (HAMRS, LoTW, eQSL, Club Log)

extension SyncService {
    func downloadFromHAMRS(timeout: TimeInterval) async -> (
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

    func fetchLoTWCallsigns(debugLog: SyncDebugLog) async -> [String] {
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

    func downloadFromLoTW(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run {
            self.syncPhase = .downloading(service: .lotw)
            self.serviceSyncStates[.lotw] = .downloading
        }
        let debugLog = SyncDebugLog.shared
        let rxSince = lotwClient.getLastQSORxDate()
        let qslSince = lotwClient.getLastQSLSinceDate()
        let syncStartTime = Date()
        debugLog.info("Starting LoTW download", service: .lotw)

        let userCallsigns = await fetchLoTWCallsigns(debugLog: debugLog)

        do {
            let response = try await withTimeout(seconds: timeout, service: .lotw) {
                try await self.lotwClient.fetchQSOs(
                    forCallsigns: userCallsigns, qsoRxSince: rxSince
                )
            }
            debugLog.info("Downloaded \(response.qsos.count) QSOs from LoTW", service: .lotw)

            var fetched = response.qsos.map { FetchedQSO.fromLoTW($0) }

            if let lastQSORx = response.lastQSORx {
                try lotwClient.saveLastQSORxDate(lastQSORx)
            }

            fetched = await mergeLoTWConfirmations(
                fetched: fetched, callsigns: userCallsigns,
                qslSince: qslSince, timeout: timeout
            )

            try lotwClient.saveLastQSLSinceDate(syncStartTime)
            logLoTWSamples(response: response, fetched: fetched, debugLog: debugLog)

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

    private func mergeLoTWConfirmations(
        fetched: [FetchedQSO], callsigns: [String],
        qslSince: Date?, timeout: TimeInterval
    ) async -> [FetchedQSO] {
        guard let qslSince else {
            return fetched
        }
        let confirmations = await fetchLoTWConfirmations(
            callsigns: callsigns, qslSince: qslSince, timeout: timeout
        )
        guard !confirmations.isEmpty else {
            return fetched
        }
        lastLoTWQslsReceived += confirmations.count
        SyncDebugLog.shared.info(
            "Downloaded \(confirmations.count) new LoTW confirmations",
            service: .lotw
        )
        return fetched + confirmations
    }

    private func logLoTWSamples(
        response: LoTWResponse, fetched: [FetchedQSO], debugLog: SyncDebugLog
    ) {
        for (index, qso) in response.qsos.prefix(5).enumerated() {
            debugLog.logRawQSO(
                service: .lotw,
                rawJSON: qso.rawADIF,
                parsedFields: fetched[index].debugFields
            )
        }
    }

    /// Fetch newly confirmed QSOs from LoTW. Non-fatal — returns empty on failure.
    func fetchLoTWConfirmations(
        callsigns: [String], qslSince: Date, timeout: TimeInterval
    ) async -> [FetchedQSO] {
        let debugLog = SyncDebugLog.shared
        do {
            let response = try await withTimeout(seconds: timeout, service: .lotw) {
                try await self.lotwClient.fetchNewConfirmations(
                    forCallsigns: callsigns, qslSince: qslSince
                )
            }
            return response.qsos.map { FetchedQSO.fromLoTW($0) }
        } catch {
            debugLog.warning(
                "LoTW confirmation fetch failed (non-fatal): \(error.localizedDescription)",
                service: .lotw
            )
            return []
        }
    }

    func downloadFromEQSL(timeout: TimeInterval) async -> (
        ServiceType, Result<[FetchedQSO], Error>
    ) {
        await MainActor.run {
            self.syncPhase = .downloading(service: .eqsl)
            self.serviceSyncStates[.eqsl] = .downloading
        }
        let debugLog = SyncDebugLog.shared

        let lastDownload = eqslClient.getLastDownloadDate()
        let syncStartTime = Date()

        if let lastDownload {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            debugLog.info(
                "Starting incremental eQSL download "
                    + "(since \(formatter.string(from: lastDownload)))",
                service: .eqsl
            )
        } else {
            debugLog.info(
                "Starting full eQSL download (no previous sync)",
                service: .eqsl
            )
        }

        do {
            let qsos = try await withTimeout(seconds: timeout, service: .eqsl) {
                try await self.eqslClient.fetchQSOs(since: lastDownload)
            }
            debugLog.info(
                "Downloaded \(qsos.count) QSOs from eQSL", service: .eqsl
            )
            let fetched = qsos.map { FetchedQSO.fromEQSL($0) }

            eqslClient.saveLastDownloadDate(syncStartTime)

            await MainActor.run {
                self.syncProgress.addDownloaded(fetched.count, for: .eqsl)
                self.serviceSyncStates[.eqsl] = .downloaded(
                    count: fetched.count
                )
            }
            return (.eqsl, .success(fetched))
        } catch {
            debugLog.error(
                "eQSL download failed: \(error.localizedDescription)",
                service: .eqsl
            )
            await MainActor.run {
                self.serviceSyncStates[.eqsl] = .error(
                    error.localizedDescription
                )
            }
            return (.eqsl, .failure(error))
        }
    }

    func downloadFromClubLog(timeout: TimeInterval) async -> (
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
