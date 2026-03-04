import CarrierWaveData
import Foundation

// MARK: - POTA Upload Dedup Filter

extension SyncService {
    /// Filter out QSOs that POTA already has from the upload groups.
    /// Uses the remote QSO map downloaded in the same sync cycle to prevent duplicate uploads.
    /// Returns the number of QSOs skipped as already present.
    ///
    /// Memory: O(1) per QSO — lookups against the existing `potaRemoteQSOMap` hash sets.
    /// No additional bulk loading; dedup keys are small transient strings.
    func filterAlreadyUploadedPOTAQSOs(
        _ expandedByParkAndDate: inout [String: [QSO]]
    ) -> Int {
        guard let remoteMap = potaRemoteQSOMap, !remoteMap.isEmpty else {
            SyncDebugLog.shared.warning(
                "Pre-upload dedup: remote map is \(potaRemoteQSOMap == nil ? "nil" : "empty")"
                    + " — cannot filter duplicates",
                service: .pota
            )
            return 0
        }

        var totalSkipped = 0
        for (key, parkQSOs) in expandedByParkAndDate {
            let result = filterActivationGroup(
                key: key, parkQSOs: parkQSOs, remoteMap: remoteMap
            )
            expandedByParkAndDate[key] = result.filtered
            totalSkipped += result.skipped
        }
        return totalSkipped
    }

    /// Filter a single activation group against the remote map.
    private func filterActivationGroup(
        key: String, parkQSOs: [QSO], remoteMap: POTARemoteQSOMap
    ) -> (filtered: [QSO], skipped: Int) {
        let parts = key.split(separator: "|")
        guard parts.count == 2, let myCallsign = parkQSOs.first?.myCallsign else {
            return (parkQSOs, 0)
        }
        let parkRef = String(parts[0])
        let dateStr = String(parts[1])
        let normalizedCall = POTAClient.normalizeCallsign(myCallsign)
        let activationKey = "\(parkRef.uppercased())|\(normalizedCall)|\(dateStr)"

        guard let remoteSet = remoteMap[activationKey] else {
            logActivationKeyMiss(
                activationKey: activationKey, parkRef: parkRef,
                dateStr: dateStr, qsoCount: parkQSOs.count, remoteMap: remoteMap
            )
            return (parkQSOs, 0)
        }

        var filtered: [QSO] = []
        var skipped = 0
        for qso in parkQSOs {
            let dedupKey = buildPOTAUploadDedupKey(qso)
            if remoteSet.contains(dedupKey) {
                markAlreadyPresentOnPOTA(qso, parkRef: parkRef)
                skipped += 1
            } else {
                logDedupMiss(qso: qso, dedupKey: dedupKey, remoteSet: remoteSet, missIndex: filtered.count)
                filtered.append(qso)
            }
        }
        return (filtered, skipped)
    }

    /// Log diagnostic info when activation key not found in remote map.
    /// Shows available keys for the same park to reveal format differences.
    private func logActivationKeyMiss(
        activationKey: String, parkRef: String, dateStr: String,
        qsoCount: Int, remoteMap: POTARemoteQSOMap
    ) {
        let parkPrefix = parkRef.uppercased() + "|"
        let available = remoteMap.keys
            .filter { $0.hasPrefix(parkPrefix) && $0.hasSuffix("|\(dateStr)") }
            .prefix(3)
            .joined(separator: ", ")
        let msg = available.isEmpty
            ? "no remote keys for \(parkRef) on \(dateStr)"
            : "available keys: [\(available)]"
        SyncDebugLog.shared.warning(
            "Pre-upload dedup: no match for \(activationKey)"
                + " — \(qsoCount) QSO(s) bypass dedup (\(msg))",
            service: .pota
        )
    }

    /// Log diagnostic info when a QSO is not found in the remote set (first 3 only).
    private func logDedupMiss(qso: QSO, dedupKey: String, remoteSet: Set<String>, missIndex: Int) {
        guard missIndex < 3 else {
            return
        }
        let callPrefix = qso.callsign.uppercased().trimmingCharacters(in: .whitespaces) + "|"
        let closest = remoteSet.first { $0.hasPrefix(callPrefix) }
        SyncDebugLog.shared.debug(
            "Pre-upload dedup miss: local=\(dedupKey) closest=\(closest ?? "none")"
                + " remoteCount=\(remoteSet.count)",
            service: .pota
        )
    }

    /// Filter out QSOs with invalid bands that POTA will reject.
    /// Returns the rejected QSOs so the caller can alert the user.
    func filterInvalidBandQSOs(
        _ expandedByParkAndDate: inout [String: [QSO]]
    ) -> [QSO] {
        var rejected: [QSO] = []

        for (key, parkQSOs) in expandedByParkAndDate {
            let parkRef = String(key.split(separator: "|").first ?? "")
            var valid: [QSO] = []
            for qso in parkQSOs {
                if qso.band.isEmpty || qso.band.uppercased() == "UNKNOWN" {
                    // Mark as rejected so we don't keep retrying
                    if let presence = qso.potaPresence(forPark: parkRef) {
                        presence.needsUpload = false
                        presence.uploadRejected = true
                    }
                    rejected.append(qso)
                } else {
                    valid.append(qso)
                }
            }
            expandedByParkAndDate[key] = valid
        }

        return rejected
    }

    /// Build a dedup key from a local QSO for comparison against the POTA remote set.
    /// Format matches `buildRemoteDedupKey` in POTAClient+Adaptive:
    /// "WORKEDCALL|BAND|MODE|HHMM" where HHMM is 2-minute bucketed UTC.
    private func buildPOTAUploadDedupKey(_ qso: QSO) -> String {
        let call = qso.callsign.uppercased().trimmingCharacters(in: .whitespaces)
        let band = qso.band.uppercased().trimmingCharacters(in: .whitespaces)
        let mode = POTAClient.normalizeModeForDedup(qso.mode)
        let time = bucketUploadTime(qso.timestamp)
        return "\(call)|\(band)|\(mode)|\(time)"
    }

    /// Bucket a timestamp to 2-minute resolution (round down to even minutes).
    /// Returns "HHMM" in UTC. Matches `bucketTime` in QSOProcessingActor+POTAGapRepair.
    private func bucketUploadTime(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(in: utc, from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let bucketed = minute - (minute % 2)
        return String(format: "%02d%02d", hour, bucketed)
    }

    /// Mark a QSO as already present on POTA for a specific park.
    /// Clears needsUpload and sets isPresent so subsequent gap repair won't re-flag it.
    private func markAlreadyPresentOnPOTA(_ qso: QSO, parkRef: String) {
        if let presence = qso.potaPresence(forPark: parkRef) {
            presence.needsUpload = false
            presence.isPresent = true
            presence.isSubmitted = false
            presence.lastConfirmedAt = Date()
        }
    }

    /// Alert the user about QSOs with invalid bands that can't be uploaded
    func logBadBandQSOs(_ qsos: [QSO]) async {
        let callsigns = qsos.prefix(5).map { "\($0.callsign) (band=\($0.band))" }
            .joined(separator: ", ")
        let more = qsos.count > 5 ? " (+\(qsos.count - 5) more)" : ""
        await MainActor.run {
            SyncDebugLog.shared.actionRequired(
                "\(qsos.count) QSO(s) have invalid band and cannot upload to POTA"
                    + " — edit in Logs to fix: \(callsigns)\(more)",
                service: .pota
            )
        }
    }

    /// Log QSOs that need POTA upload but have no park reference
    func logPOTAQSOsWithoutPark(_ qsos: [QSO]) async {
        guard !qsos.isEmpty else {
            return
        }
        let callsigns = qsos.prefix(5).map(\.callsign).joined(separator: ", ")
        let more = qsos.count > 5 ? " (+\(qsos.count - 5) more)" : ""
        await MainActor.run {
            SyncDebugLog.shared.warning(
                "\(qsos.count) QSO(s) need POTA upload but have no park reference: "
                    + "\(callsigns)\(more)",
                service: .pota
            )
        }
    }

    /// Log POTA upload start with metadata filtering info and content summary
    func logPOTAUploadStart(qsos: [QSO], realQsos: [QSO], parkCount: Int) async {
        let metadataCount = qsos.count - realQsos.count
        await MainActor.run {
            if metadataCount > 0 {
                SyncDebugLog.shared.debug(
                    "Filtered out \(metadataCount) metadata QSO(s) from POTA upload",
                    service: .pota
                )
            }
            let bands = Set(realQsos.map(\.band)).sorted().joined(separator: ", ")
            let modes = Set(realQsos.map(\.mode)).sorted().joined(separator: ", ")
            SyncDebugLog.shared.debug(
                "POTA upload: \(realQsos.count) QSO(s) across \(parkCount) park(s) "
                    + "bands=[\(bands)] modes=[\(modes)]",
                service: .pota
            )
        }
    }
}
