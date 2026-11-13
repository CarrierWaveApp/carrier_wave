import Foundation

// MARK: - POTAUserStats

/// Public user statistics from POTA (no auth required).
/// Endpoint: GET https://api.pota.app/stats/user/{callsign}
struct POTAUserStats: Decodable {
    struct ActivatorStats: Decodable {
        let activations: Int
        let parks: Int
        let qsos: Int
    }

    let callsign: String
    let activator: ActivatorStats?
}

// MARK: - POTADownloadAudit

/// Audit trail for POTA download operations.
/// Captures per-activation discrepancies to help diagnose missing activations or QSOs.
struct POTADownloadAudit {
    // MARK: Internal

    /// A single discrepancy found during download audit.
    struct Discrepancy {
        enum Kind: String {
            case qsoCountMismatch = "QSO_COUNT_MISMATCH"
            case modeBreakdownMismatch = "MODE_BREAKDOWN_MISMATCH"
            case timestampOutOfRange = "TIMESTAMP_OUT_OF_RANGE"
            case duplicateQsoId = "DUPLICATE_QSO_ID"
            case nilBandOrMode = "NIL_BAND_OR_MODE"
            case activationCountMismatch = "ACTIVATION_COUNT_MISMATCH"
            case totalQsoCountMismatch = "TOTAL_QSO_COUNT_MISMATCH"
            case parkCountMismatch = "PARK_COUNT_MISMATCH"
        }

        let activation: String // "REF|DATE"
        let kind: Kind
        let detail: String
        /// When true, the discrepancy has a known benign explanation (e.g. failed activations).
        var isExpected: Bool = false
    }

    /// Summary of activation-level counts for the entire download.
    struct Summary {
        let totalActivationsFromAPI: Int
        let activationsProcessed: Int
        let activationsSkipped: Int
        let totalQSOsExpected: Int
        let totalQSOsDownloaded: Int
        let discrepancyCount: Int
        let oldestActivationDate: String?
    }

    private(set) var discrepancies: [Discrepancy] = []
    private(set) var perActivationExpected: [String: Int] = [:]
    private(set) var perActivationDownloaded: [String: Int] = [:]
    private(set) var activationsFromAPICount: Int = 0
    private(set) var oldestActivationDate: String?
    private(set) var allUserStats: [POTAUserStats] = []

    var hasDiscrepancies: Bool {
        !discrepancies.isEmpty
    }

    // MARK: - Recording

    /// Record the API-level activation list metadata.
    mutating func recordActivationList(
        apiCount: Int,
        activations: [POTARemoteActivation]
    ) {
        activationsFromAPICount = apiCount
        oldestActivationDate = activations.map(\.date).min()
    }

    /// Compare downloaded activations against the public user stats endpoint.
    /// Filters activations to only those matching the stats callsign so
    /// multi-callsign users (vanity call upgrade) get accurate per-call audits.
    mutating func recordUserStats(
        _ stats: POTAUserStats,
        activations: [POTARemoteActivation]
    ) {
        allUserStats.append(stats)
        guard let activator = stats.activator else {
            return
        }

        let call = stats.callsign
        let callActivations = activations.filter {
            $0.callsign.uppercased() == call.uppercased()
        }

        if callActivations.count != activator.activations {
            let failedCount = callActivations.filter { $0.total < 10 }.count
            let successfulCount = callActivations.count - failedCount
            let explainedByFailed = successfulCount == activator.activations

            let detail = if explainedByFailed {
                "[\(call)] Profile says \(activator.activations) activations,"
                    + " API returned \(callActivations.count)"
                    + " (\(failedCount) have <10 QSOs — not counted by POTA)"
            } else {
                "[\(call)] Profile says \(activator.activations) activations,"
                    + " API returned \(callActivations.count)"
                    + " (\(failedCount) failed, \(successfulCount) successful)"
            }

            discrepancies.append(Discrepancy(
                activation: "ALL|\(call)",
                kind: .activationCountMismatch,
                detail: detail,
                isExpected: explainedByFailed
            ))
        }

        let totalQSOs = callActivations.reduce(into: 0) { $0 += $1.total }
        if totalQSOs != activator.qsos {
            discrepancies.append(Discrepancy(
                activation: "ALL|\(call)",
                kind: .totalQsoCountMismatch,
                detail: "[\(call)] Profile says \(activator.qsos) QSOs,"
                    + " activations sum to \(totalQSOs)"
            ))
        }

        let uniqueParks = Set(callActivations.map(\.reference))
        if uniqueParks.count != activator.parks {
            discrepancies.append(Discrepancy(
                activation: "ALL|\(call)",
                kind: .parkCountMismatch,
                detail: "[\(call)] Profile says \(activator.parks) parks,"
                    + " activations reference \(uniqueParks.count)"
            ))
        }
    }

    /// Audit a single activation's downloaded QSOs against its declared metadata.
    mutating func auditActivation(
        _ activation: POTARemoteActivation,
        downloadedQSOs: [POTARemoteQSO]
    ) {
        let key = "\(activation.reference)|\(activation.date)"
        perActivationExpected[key] = activation.total
        perActivationDownloaded[key] = downloadedQSOs.count

        checkQSOCount(key: key, activation: activation, downloaded: downloadedQSOs.count)
        checkModeBreakdown(key: key, activation: activation)
        checkTimestampRange(key: key, activation: activation, qsos: downloadedQSOs)
        checkDuplicateIds(key: key, qsos: downloadedQSOs)
        checkNilFields(key: key, qsos: downloadedQSOs)
    }

    /// Build a summary for logging.
    func buildSummary(activationsSkipped: Int) -> Summary {
        let totalExpected = perActivationExpected.values.reduce(into: 0) { $0 += $1 }
        let totalDownloaded = perActivationDownloaded.values.reduce(into: 0) { $0 += $1 }
        return Summary(
            totalActivationsFromAPI: activationsFromAPICount,
            activationsProcessed: perActivationExpected.count,
            activationsSkipped: activationsSkipped,
            totalQSOsExpected: totalExpected,
            totalQSOsDownloaded: totalDownloaded,
            discrepancyCount: discrepancies.count,
            oldestActivationDate: oldestActivationDate
        )
    }

    // MARK: Private

    // MARK: - Individual Checks

    private mutating func checkQSOCount(
        key: String, activation: POTARemoteActivation, downloaded: Int
    ) {
        if downloaded != activation.total {
            discrepancies.append(Discrepancy(
                activation: key,
                kind: .qsoCountMismatch,
                detail: "Expected \(activation.total), got \(downloaded)"
            ))
        }
    }

    private mutating func checkModeBreakdown(
        key: String, activation: POTARemoteActivation
    ) {
        let modeSum = activation.cw + activation.data + activation.phone
        if modeSum != activation.total {
            discrepancies.append(Discrepancy(
                activation: key,
                kind: .modeBreakdownMismatch,
                detail: "CW(\(activation.cw))+DATA(\(activation.data))"
                    + "+PHONE(\(activation.phone))=\(modeSum) != total(\(activation.total))"
            ))
        }
    }

    private mutating func checkTimestampRange(
        key: String, activation: POTARemoteActivation, qsos: [POTARemoteQSO]
    ) {
        guard let firstStr = activation.firstQso,
              let lastStr = activation.lastQso,
              !qsos.isEmpty
        else {
            return
        }

        // Compare as strings since format is ISO 8601 and lexicographic ordering works
        var outOfRange = 0
        for qso in qsos {
            let ts = qso.qsoDateTime
            if ts < firstStr || ts > lastStr {
                outOfRange += 1
            }
        }
        if outOfRange > 0 {
            discrepancies.append(Discrepancy(
                activation: key,
                kind: .timestampOutOfRange,
                detail: "\(outOfRange) QSO(s) outside [\(firstStr), \(lastStr)]"
            ))
        }
    }

    private mutating func checkDuplicateIds(key: String, qsos: [POTARemoteQSO]) {
        let allIds = qsos.map(\.qsoId)
        let uniqueIds = Set(allIds)
        let dupeCount = allIds.count - uniqueIds.count
        if dupeCount > 0 {
            discrepancies.append(Discrepancy(
                activation: key,
                kind: .duplicateQsoId,
                detail: "\(dupeCount) duplicate qsoId(s)"
            ))
        }
    }

    private mutating func checkNilFields(key: String, qsos: [POTARemoteQSO]) {
        let nilCount = qsos.filter { $0.band == nil || $0.mode == nil }.count
        if nilCount > 0 {
            discrepancies.append(Discrepancy(
                activation: key,
                kind: .nilBandOrMode,
                detail: "\(nilCount) QSO(s) with nil band or mode (will be dropped)"
            ))
        }
    }
}

// MARK: - POTADownloadAudit Logging

extension POTADownloadAudit {
    /// Log audit summary and any discrepancies to the sync debug log.
    @MainActor
    func logResults(activationsSkipped: Int) {
        let debugLog = SyncDebugLog.shared
        let summary = buildSummary(activationsSkipped: activationsSkipped)

        debugLog.info(
            "POTA Audit: \(summary.activationsProcessed) activations processed"
                + " (\(summary.activationsSkipped) skipped),"
                + " \(summary.totalQSOsDownloaded)/\(summary.totalQSOsExpected) QSOs downloaded"
                + (summary.oldestActivationDate.map { ", oldest=\($0)" } ?? ""),
            service: .pota
        )

        if summary.totalActivationsFromAPI != summary.activationsProcessed + summary.activationsSkipped {
            let missing = summary.totalActivationsFromAPI
                - summary.activationsProcessed - summary.activationsSkipped
            debugLog.warning(
                "POTA Audit: \(missing) activation(s) unaccounted for"
                    + " (API reported \(summary.totalActivationsFromAPI))",
                service: .pota
            )
        }

        for stats in allUserStats {
            guard let activator = stats.activator else {
                continue
            }
            debugLog.info(
                "POTA Audit profile (\(stats.callsign)):"
                    + " \(activator.activations) activations,"
                    + " \(activator.parks) parks, \(activator.qsos) QSOs",
                service: .pota
            )
        }

        logDiscrepancies(to: debugLog)
    }

    @MainActor
    private func logDiscrepancies(to debugLog: SyncDebugLog) {
        if discrepancies.isEmpty {
            debugLog.info("POTA Audit: No discrepancies found", service: .pota)
            return
        }

        let unexpectedCount = discrepancies.filter { !$0.isExpected }.count
        if unexpectedCount > 0 {
            debugLog.warning(
                "POTA Audit: \(discrepancies.count) discrepancy(ies) found",
                service: .pota
            )
        } else {
            debugLog.info(
                "POTA Audit: \(discrepancies.count) discrepancy(ies) found (all expected)",
                service: .pota
            )
        }
        for disc in discrepancies {
            let msg = "POTA Audit [\(disc.kind.rawValue)] \(disc.activation): \(disc.detail)"
            if disc.isExpected {
                debugLog.info(msg, service: .pota)
            } else {
                debugLog.warning(msg, service: .pota)
            }
        }
    }
}
