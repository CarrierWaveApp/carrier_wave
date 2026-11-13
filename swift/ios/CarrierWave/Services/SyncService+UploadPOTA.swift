import CarrierWaveData
import Foundation
import SwiftData

// MARK: - SyncService POTA Upload Methods

extension SyncService {
    func uploadToPOTA(qsos: [QSO]) async throws -> Int {
        let uploadStartTime = Date()

        // Filter out metadata pseudo-modes before processing
        let realQsos = qsos.filter { !QSOMode.isMetadata($0.mode) }

        var expandedByParkAndDate = groupQSOsByParkAndDate(realQsos)

        // Reject QSOs with ADIF spec violations — POTA will reject them anyway
        let badADIFQSOs = filterInvalidADIFQSOs(&expandedByParkAndDate)
        if !badADIFQSOs.isEmpty {
            await recordADIFValidationFailures(badADIFQSOs)
        }

        // Filter out QSOs that POTA already has (prevents duplicate upload loop).
        // Uses potaRemoteQSOMap downloaded in the same sync cycle — O(1) lookups.
        let skippedDuplicates = filterAlreadyUploadedPOTAQSOs(&expandedByParkAndDate)
        expandedByParkAndDate = expandedByParkAndDate.filter { !$0.value.isEmpty }

        if skippedDuplicates > 0 {
            await MainActor.run {
                SyncDebugLog.shared.info(
                    "Pre-upload dedup: skipped \(skippedDuplicates) QSO(s) already on POTA",
                    service: .pota
                )
            }
        }

        var totalUploaded = 0
        var totalFailed = 0
        let parkRefs = Set(expandedByParkAndDate.keys.compactMap {
            $0.split(separator: "|").first.map(String.init)
        })

        await logPOTAUploadStart(
            qsos: qsos, realQsos: realQsos, parkCount: parkRefs.count
        )

        for (key, parkQSOs) in expandedByParkAndDate {
            let parkRef = String(key.split(separator: "|").first ?? "")
            let result = await uploadParkToPOTA(parkRef: parkRef, parkQSOs: parkQSOs)
            totalUploaded += result.uploaded
            totalFailed += result.failed
        }

        // Log final state with total timing
        let totalDurationMs = Int(Date().timeIntervalSince(uploadStartTime) * 1_000)
        await MainActor.run {
            SyncDebugLog.shared.info(
                "POTA upload complete: \(totalUploaded) accepted, "
                    + "\(totalFailed) failed (\(totalDurationMs)ms total)",
                service: .pota
            )
        }
        return totalUploaded
    }

    /// Group QSOs by (park, UTC date) so each upload matches a single POTA activation.
    /// Without date grouping, multi-date uploads create jobs whose firstQSO date
    /// only covers one date, causing the reconciliation to reset QSOs from other
    /// dates back to needsUpload (producing duplicate uploads on every sync).
    func groupQSOsByParkAndDate(_ qsos: [QSO]) -> [String: [QSO]] {
        var result: [String: [QSO]] = [:]
        for qso in qsos {
            guard let parkRef = qso.parkReference, !parkRef.isEmpty else {
                continue
            }
            let parks = POTAClient.splitParkReferences(parkRef)
            let dateStr = Self.utcDateFormatter.string(from: qso.timestamp)
            for park in parks {
                let key = "\(park)|\(dateStr)"
                result[key, default: []].append(qso)
            }
        }
        return result
    }

    /// UTC date formatter for grouping QSOs by activation date
    static let utcDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Upload QSOs for a single park to POTA (handles both single-park and two-fer QSOs)
    func uploadParkToPOTA(parkRef: String, parkQSOs: [QSO]) async -> (
        uploaded: Int, failed: Int
    ) {
        let parkStartTime = Date()
        await MainActor.run {
            SyncDebugLog.shared.info(
                "Starting upload of \(parkQSOs.count) QSO(s) to park \(parkRef)",
                service: .pota
            )
        }

        do {
            let result = try await potaClient.uploadActivationWithRecording(
                parkReference: parkRef,
                qsos: parkQSOs,
                modelContext: modelContext
            )
            let parkDurationMs = Int(Date().timeIntervalSince(parkStartTime) * 1_000)

            if result.success {
                markParkQSOsSubmitted(
                    parkRef: parkRef, parkQSOs: parkQSOs,
                    result: result, durationMs: parkDurationMs
                )
                return (uploaded: result.qsosAccepted, failed: 0)
            } else {
                await MainActor.run {
                    SyncDebugLog.shared.warning(
                        "Park \(parkRef): upload returned success=false (\(parkDurationMs)ms)",
                        service: .pota
                    )
                    logFailedQSOs(parkQSOs, reason: "upload returned success=false")
                }
                return (uploaded: 0, failed: parkQSOs.count)
            }
        } catch POTAError.invalidParkReference {
            let parkDurationMs = Int(Date().timeIntervalSince(parkStartTime) * 1_000)
            await rejectInvalidParkQSOs(
                parkRef: parkRef, parkQSOs: parkQSOs, durationMs: parkDurationMs
            )
            return (uploaded: 0, failed: parkQSOs.count)
        } catch {
            let parkDurationMs = Int(Date().timeIntervalSince(parkStartTime) * 1_000)
            await MainActor.run {
                SyncDebugLog.shared.error(
                    "Park \(parkRef): \(error.localizedDescription) (\(parkDurationMs)ms)",
                    service: .pota
                )
                logFailedQSOs(parkQSOs, reason: error.localizedDescription)
            }
            return (uploaded: 0, failed: parkQSOs.count)
        }
    }

    /// Log and record diagnostics for QSOs that failed ADIF validation.
    private func recordADIFValidationFailures(_ qsos: [QSO]) async {
        await logBadADIFQSOs(qsos)
        await MainActor.run {
            UploadDiagnosticStore.shared.record(
                UploadErrorClassifier.validationDiagnostic(
                    service: .pota,
                    message: "\(qsos.count) QSO(s) have invalid ADIF fields",
                    guidance: "Edit these QSOs in Logs to fix invalid mode or band values. "
                        + "If you see upload errors, please reach out on the Carrier Wave "
                        + "Discord before contacting POTA directly.",
                    affectedCount: qsos.count
                )
            )
        }
    }
}
