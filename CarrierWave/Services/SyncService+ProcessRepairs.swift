import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - SyncService Repair Methods

extension SyncService {
    /// Compare local POTA QSOs against what POTA's API returned per-activation.
    /// Flags missing QSOs as needsUpload=true for re-upload.
    func repairPOTAGapsAsync(remoteQSOMap: POTARemoteQSOMap) async {
        do {
            let result = try await Self.processingActor.repairPOTAGaps(
                remoteQSOMap: remoteQSOMap,
                container: modelContext.container
            )
            if result.gapsFound > 0 {
                SyncDebugLog.shared.warning(
                    "POTA gap repair: checked \(result.activationsChecked) activations, "
                        + "found \(result.gapsFound) missing QSOs -- flagged for re-upload",
                    service: .pota
                )
            } else {
                SyncDebugLog.shared.debug(
                    "POTA gap repair: checked \(result.activationsChecked) activations, no gaps",
                    service: .pota
                )
            }
        } catch {
            SyncDebugLog.shared.error("POTA gap repair failed: \(error)", service: .pota)
        }
    }

    /// Detect and repair QSOs missing ServicePresence records for a service.
    func repairOrphanedQSOsAsync(for service: ServiceType) async {
        let debugLog = SyncDebugLog.shared
        let aliasService = CallsignAliasService.shared
        let userCallsigns = aliasService.getAllUserCallsigns()

        do {
            let result = try await Self.processingActor.repairOrphanedQSOs(
                for: [service], userCallsigns: userCallsigns, container: modelContext.container
            )
            if result.orphanedQSOs.isEmpty {
                debugLog.debug(
                    "No orphaned QSOs found for \(service.displayName)", service: service
                )
            } else {
                let msg =
                    "Found \(result.orphanedQSOs.count) QSOs without \(service.displayName) "
                        + "presence - created \(result.repairedCount) ServicePresence records:"
                debugLog.warning(msg, service: service)
                let dateFmt = ISO8601DateFormatter()
                dateFmt.formatOptions = [.withInternetDateTime]
                for (idx, qso) in result.orphanedQSOs.prefix(10).enumerated() {
                    let ts = dateFmt.string(from: qso.timestamp)
                    let svcs = qso.missingServices.map(\.displayName).joined(separator: ", ")
                    let detail =
                        "  \(idx + 1). \(qso.callsign) \(qso.band) \(qso.mode) @ \(ts) "
                            + "(my: \(qso.myCallsign)) - missing: \(svcs)"
                    debugLog.warning(detail, service: service)
                }
                if result.orphanedQSOs.count > 10 {
                    debugLog.warning(
                        "  ... and \(result.orphanedQSOs.count - 10) more", service: service
                    )
                }
            }
        } catch {
            debugLog.error("Failed to repair orphaned QSOs: \(error)", service: service)
        }
    }

    /// Clear needsUpload flags on hidden (soft-deleted) QSOs.
    func clearHiddenQSOUploadFlagsAsync() async {
        do {
            let result = try await Self.processingActor.clearHiddenQSOUploadFlags(
                container: modelContext.container
            )
            if result.clearedCount > 0 {
                let msg =
                    "Cleared needsUpload on \(result.clearedCount) hidden (soft-deleted) QSO(s)"
                SyncDebugLog.shared.warning(msg)
            }
        } catch {
            SyncDebugLog.shared.error("Failed to clear hidden QSO upload flags: \(error)")
        }
    }

    /// Clear needsUpload flags on metadata pseudo-modes (WEATHER, SOLAR, NOTE from Ham2K PoLo).
    func clearMetadataUploadFlagsAsync() async {
        do {
            let result = try await Self.processingActor.clearMetadataUploadFlags(
                container: modelContext.container
            )
            if result.clearedCount > 0 {
                let msg =
                    "Cleared needsUpload on \(result.clearedCount) metadata QSO(s) (WEATHER/SOLAR/NOTE)"
                SyncDebugLog.shared.info(msg)
            }
        } catch {
            SyncDebugLog.shared.error("Failed to clear metadata upload flags: \(error)")
        }
    }

    /// Clear needsUpload flags on QSOs logged under non-primary callsigns.
    func clearNonPrimaryCallsignUploadFlagsAsync() async {
        let primaryCallsign = CallsignAliasService.shared.getCurrentCallsign()
        do {
            let result = try await Self.processingActor.clearNonPrimaryCallsignUploadFlags(
                primaryCallsign: primaryCallsign, container: modelContext.container
            )
            if result.clearedCount > 0 {
                let msg =
                    "Cleared needsUpload on \(result.clearedCount) QSO(s) from non-primary callsigns"
                SyncDebugLog.shared.info(msg)
                for (call, count) in result.byCallsign.sorted(by: { $0.value > $1.value }) {
                    SyncDebugLog.shared.debug("  - \(call): \(count) QSO(s)")
                }
            }
        } catch {
            SyncDebugLog.shared.error("Failed to clear non-primary callsign upload flags: \(error)")
        }
    }

    /// Clear bogus HAMRS needsUpload flags created when supportsUpload was incorrectly true.
    func clearBogusHamrsUploadFlagsAsync() async {
        do {
            let result = try await Self.processingActor.clearBogusHamrsUploadFlags(
                container: modelContext.container
            )
            if result.clearedCount > 0 {
                SyncDebugLog.shared.warning(
                    "Cleared \(result.clearedCount) bogus HAMRS needsUpload flag(s)"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Failed to clear HAMRS upload flags: \(error)")
        }
    }

    /// Repair QRZ ServicePresence records stuck in dead state
    /// (isPresent=false, needsUpload=false, not submitted, not rejected).
    func repairQRZDeadStateAsync() async {
        do {
            let result = try await Self.processingActor.repairQRZDeadStateQSOs(
                container: modelContext.container
            )
            if result.repairedCount > 0 {
                SyncDebugLog.shared.warning(
                    "Repaired \(result.repairedCount) QRZ dead-state QSO(s) "
                        + "(reset to needsUpload=true)"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Failed to repair QRZ dead-state QSOs: \(error)")
        }
    }

    /// Repair POTA ServicePresence records stuck in dead state
    /// (isPresent=false, needsUpload=false, not submitted, not rejected).
    func repairPOTADeadStateAsync() async {
        do {
            let result = try await Self.processingActor.repairPOTADeadStateQSOs(
                container: modelContext.container
            )
            if result.repairedCount > 0 {
                SyncDebugLog.shared.warning(
                    "Repaired \(result.repairedCount) POTA dead-state QSO(s) "
                        + "(reset to needsUpload=true)",
                    service: .pota
                )
            }
        } catch {
            SyncDebugLog.shared.error(
                "Failed to repair POTA dead-state QSOs: \(error)", service: .pota
            )
        }
    }

    /// Repair QSOs that have DXCC in rawADIF but not in the dxcc column.
    /// This backfills DXCC data for QSOs imported before the fix was applied.
    func repairMissingDXCCAsync() async {
        do {
            let result = try await Self.processingActor.repairMissingDXCC(
                container: modelContext.container
            )
            if result.repairedCount > 0 {
                let msg =
                    "Repaired DXCC on \(result.repairedCount) QSO(s) from rawADIF "
                        + "(scanned \(result.scannedCount))"
                SyncDebugLog.shared.info(msg)
            }
        } catch {
            SyncDebugLog.shared.error("Failed to repair missing DXCC: \(error)")
        }
    }

    /// Repair QSOs with leading/trailing whitespace in callsigns.
    /// Trims whitespace, then merges any resulting duplicates.
    func repairCallsignWhitespaceAsync() async {
        do {
            let result = try await Self.processingActor.repairCallsignWhitespace(
                container: modelContext.container
            )
            if result.trimmedCount > 0 || result.mergedCount > 0 {
                SyncDebugLog.shared.warning(
                    "Callsign whitespace repair: trimmed \(result.trimmedCount), "
                        + "merged \(result.mergedCount), deleted \(result.deletedCount)"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Failed to repair callsign whitespace: \(error)")
        }
    }

    /// Repair QRZ ServicePresence records stuck in isSubmitted=true state.
    /// QRZ uploads are synchronous -- isSubmitted should have been isPresent.
    func repairQRZSubmittedStateAsync() async {
        do {
            let result = try await Self.processingActor.repairQRZSubmittedState(
                container: modelContext.container
            )
            if result.repairedCount > 0 {
                SyncDebugLog.shared.warning(
                    "Repaired \(result.repairedCount) QRZ ServicePresence record(s) "
                        + "stuck in isSubmitted state (promoted to isPresent)"
                )
            }
        } catch {
            SyncDebugLog.shared.error("Failed to repair QRZ submitted state: \(error)")
        }
    }
}
