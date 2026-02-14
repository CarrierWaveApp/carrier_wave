import CarrierWaveCore
import Foundation

// MARK: - Force Re-download Methods

extension SyncService {
    /// Force re-download all QSOs from QRZ and reprocess them
    func forceRedownloadFromQRZ() async throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Force re-downloading from QRZ", service: .qrz)

        let qsos = try await qrzClient.fetchQSOs(since: nil)
        let fetched = qsos.map { FetchedQSO.fromQRZ($0) }

        debugLog.info("Fetched \(fetched.count) QSOs from QRZ", service: .qrz)
        let result = try reprocessQSOs(fetched)
        storeReport(buildReport(
            service: .qrz, downloaded: fetched.count,
            created: result.created, merged: result.updated
        ))
        return result
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
        let result = try reprocessQSOs(fetched)
        storeReport(buildReport(
            service: .pota, downloaded: fetched.count,
            created: result.created, merged: result.updated
        ))
        return result
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
        let downloadResult = try await lofiClient.fetchAllQsos()
        let qsos = downloadResult.qsos

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
        let skipped = qsos.count - fetched.count
        let result = try reprocessQSOs(fetched)
        storeReport(buildReport(
            service: .lofi, downloaded: qsos.count, skipped: skipped,
            created: result.created, merged: result.updated
        ))
        return result
    }

    /// Force re-download all QSOs from HAMRS and reprocess them
    func forceRedownloadFromHAMRS() async throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Force re-downloading from HAMRS", service: .hamrs)

        let qsos = try await hamrsClient.fetchAllQSOs()
        let fetched = qsos.compactMap { FetchedQSO.fromHAMRS($0.0, logbook: $0.1) }
        let skipped = qsos.count - fetched.count

        debugLog.info("Fetched \(fetched.count) QSOs from HAMRS", service: .hamrs)
        let result = try reprocessQSOs(fetched)
        storeReport(buildReport(
            service: .hamrs, downloaded: qsos.count, skipped: skipped,
            created: result.created, merged: result.updated
        ))
        return result
    }

    /// Force re-download all QSOs from LoTW and reprocess them
    func forceRedownloadFromLoTW() async throws -> (updated: Int, created: Int) {
        let debugLog = SyncDebugLog.shared
        debugLog.info("Force re-downloading from LoTW", service: .lotw)

        // Get all user callsigns (current + previous) to fetch QSOs for all of them
        let userCallsigns = await MainActor.run {
            Array(CallsignAliasService.shared.getAllUserCallsigns())
        }

        if !userCallsigns.isEmpty {
            debugLog.info(
                "Fetching QSOs for callsigns: \(userCallsigns.joined(separator: ", "))",
                service: .lotw
            )
        }

        // Fetch ALL QSOs (no qsoRxSince filter)
        let response = try await lotwClient.fetchQSOs(
            forCallsigns: userCallsigns, qsoRxSince: nil
        )
        let fetched = response.qsos.map { FetchedQSO.fromLoTW($0) }

        debugLog.info("Fetched \(fetched.count) QSOs from LoTW", service: .lotw)
        let result = try reprocessQSOs(fetched)
        storeReport(buildReport(
            service: .lotw, downloaded: fetched.count,
            created: result.created, merged: result.updated
        ))
        return result
    }
}
