import CarrierWaveCore
import Foundation

// MARK: - SyncService Upload Helpers

/// Shared validation and logging helpers used by QRZ, POTA, and Club Log upload paths.
extension SyncService {
    /// Partition QSOs into valid (uploadable) and invalid (missing required fields)
    func partitionQSOsByValidity(_ qsos: [QSO]) -> (valid: [QSO], invalid: [QSO]) {
        let grouped = Dictionary(grouping: qsos) { $0.hasRequiredFieldsForUpload }
        return (valid: grouped[true] ?? [], invalid: grouped[false] ?? [])
    }

    /// Log QSOs that can't be uploaded due to missing required fields
    func logQSOsWithMissingFields(_ qsos: [QSO], service: ServiceType) async {
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
                let dateStr = Self.uploadDebugDateFormatter.string(from: qso.timestamp)
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
    func logPendingQSOs(_ qsos: [QSO], service: ServiceType) async {
        await MainActor.run {
            SyncDebugLog.shared.info(
                "Pending \(service.displayName) uploads: \(qsos.count) QSO(s)",
                service: service
            )
            for qso in qsos.prefix(10) {
                let dateStr = Self.uploadDebugDateFormatter.string(from: qso.timestamp)
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

    /// Date formatter for upload debug logging
    static let uploadDebugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Count how many QSOs need upload per service (for export confirmation)
    func countUploadsByService(_ qsos: [QSO]) -> [ServiceType: Int] {
        var counts: [ServiceType: Int] = [:]
        let services: [ServiceType] = [.qrz, .pota, .clublog]
        for service in services {
            let count = qsos.filter { $0.needsUpload(to: service) }.count
            if count > 0 {
                counts[service] = count
            }
        }
        return counts
    }

    /// Mark QSOs as submitted after successful park upload and log state transitions
    @MainActor
    func markParkQSOsSubmitted(
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

            let dateStr = Self.uploadDebugDateFormatter.string(from: qso.timestamp)
            SyncDebugLog.shared.debug(
                "markSubmittedToPark \(parkRef): \(qso.callsign) @ \(dateStr) "
                    + "[\(beforeState)] -> [\(afterState)]",
                service: .pota
            )
        }
        SyncDebugLog.shared.info(
            "Park \(parkRef): \(result.qsosAccepted) accepted, "
                + "\(parkQSOs.count) submitted in \(durationMs)ms. msg=\(result.message ?? "nil")",
            service: .pota
        )
    }
}
