import CarrierWaveData
import Foundation

// MARK: - Report Building

extension SyncService {
    /// Build a ServiceSyncReport from a full sync's per-service results.
    func buildReport(
        service: ServiceType,
        downloaded: Int,
        skipped: Int = 0,
        created: Int,
        merged: Int,
        uploaded: Int = 0,
        reconciliation: ReconciliationReport? = nil,
        error: String? = nil
    ) -> ServiceSyncReport {
        let status: SyncReportStatus = if error != nil {
            .error
        } else if skipped > 0 || reconciliation?.hasWarnings == true {
            .warning
        } else {
            .success
        }

        return ServiceSyncReport(
            service: service,
            timestamp: Date(),
            status: status,
            downloaded: downloaded,
            skipped: skipped,
            created: created,
            merged: merged,
            uploaded: uploaded,
            reconciliation: reconciliation
        )
    }

    /// Build ReconciliationReport from POTA reconcile result.
    func reconciliationReport(
        potaResult: QSOProcessingActor.POTAReconcileResult?,
        qrzResetCount: Int = 0
    ) -> ReconciliationReport? {
        guard potaResult != nil || qrzResetCount > 0 else {
            return nil
        }

        return ReconciliationReport(
            qrzResetCount: qrzResetCount,
            potaConfirmed: potaResult?.confirmedCount ?? 0,
            potaFailed: potaResult?.failedResetCount ?? 0,
            potaStale: potaResult?.staleResetCount ?? 0,
            potaOrphan: potaResult?.orphanResetCount ?? 0,
            potaInProgress: potaResult?.inProgressCount ?? 0
        )
    }

    // MARK: - Report Storage

    private static let syncReportsKey = "lastSyncReports"

    /// Store a sync report for a service and persist to disk.
    func storeReport(_ report: ServiceSyncReport) {
        lastSyncResults[report.service] = report
        persistReports()
    }

    /// Store an error report for a service.
    func storeErrorReport(service: ServiceType, error: Error) {
        let report = ServiceSyncReport(
            service: service,
            timestamp: Date(),
            status: .error,
            downloaded: 0,
            skipped: 0,
            created: 0,
            merged: 0,
            uploaded: 0,
            reconciliation: nil
        )
        lastSyncResults[service] = report
        persistReports()
    }

    /// Load persisted sync reports from UserDefaults.
    func loadPersistedReports() {
        typealias ReportMap = [ServiceType: ServiceSyncReport]
        guard let data = UserDefaults.standard.data(forKey: Self.syncReportsKey),
              let decoded = try? JSONDecoder().decode(ReportMap.self, from: data)
        else {
            return
        }
        lastSyncResults = decoded
    }

    /// Persist current reports to UserDefaults.
    private func persistReports() {
        guard let data = try? JSONEncoder().encode(lastSyncResults) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.syncReportsKey)
    }

    /// Build reports for all services after a full syncAll().
    /// Uses aggregate SyncResult plus per-service reconciliation data.
    func buildFullSyncReports(
        result: SyncResult,
        qrzResetCount: Int,
        potaReconcileResult: QSOProcessingActor.POTAReconcileResult?
    ) {
        // For full sync, newQSOs and mergedQSOs are aggregate across services.
        // We distribute proportionally based on download counts.
        let totalDownloaded = result.downloaded.values.reduce(0, +)

        for (service, downloaded) in result.downloaded {
            let fraction = totalDownloaded > 0
                ? Double(downloaded) / Double(totalDownloaded) : 0
            let created = Int(Double(result.newQSOs) * fraction)
            let merged = Int(Double(result.mergedQSOs) * fraction)
            let uploaded = result.uploaded[service] ?? 0

            var reconciliation: ReconciliationReport?
            if service == .qrz, qrzResetCount > 0 {
                reconciliation = ReconciliationReport(
                    qrzResetCount: qrzResetCount, potaConfirmed: 0,
                    potaFailed: 0, potaStale: 0, potaOrphan: 0, potaInProgress: 0
                )
            } else if service == .pota, let potaResult = potaReconcileResult {
                reconciliation = reconciliationReport(potaResult: potaResult)
            }

            let hasError = result.errors.contains {
                $0.starts(with: service.displayName)
            }

            storeReport(buildReport(
                service: service,
                downloaded: downloaded,
                created: created,
                merged: merged,
                uploaded: uploaded,
                reconciliation: reconciliation,
                error: hasError ? "Sync error" : nil
            ))
        }

        // Store error reports for services that failed entirely
        for errorMsg in result.errors {
            for service in ServiceType.allCases {
                let isServiceError = errorMsg.starts(with: service.displayName)
                let notAlreadyReported = lastSyncResults[service] == nil
                if isServiceError, notAlreadyReported {
                    storeErrorReport(service: service, error: SyncTimeoutError.timeout(service: service))
                }
            }
        }
    }
}
