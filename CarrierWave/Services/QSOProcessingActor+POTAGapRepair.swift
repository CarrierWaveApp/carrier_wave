import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - POTA Gap Repair Types

/// Maps activation keys ("PARKREF|CALLSIGN|YYYY-MM-DD") to sets of dedup keys
/// ("WORKEDCALL|BAND|MODE|HHMM") representing QSOs that POTA has for that activation.
typealias POTARemoteQSOMap = [String: Set<String>]

// MARK: - POTA QSO-Level Gap Repair

extension QSOProcessingActor {
    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    private static let gapRepairMetadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    struct POTAGapRepairResult: Sendable {
        let activationsChecked: Int
        let gapsFound: Int
        let deadStateRecovered: Int
    }

    /// Mutable state accumulated during gap repair iteration.
    private struct GapRepairState {
        var activationsChecked = Set<String>()
        var gapsFound = 0
        var deadStateRecovered = 0
        var unsavedCount = 0
    }

    /// Compare local POTA QSOs against what POTA's API returned per-activation.
    /// - isPresent=true but not in remote set → reset to needsUpload (gap)
    /// - Dead state (isPresent=false, needsUpload=false) but IS in remote set → recover to isPresent
    func repairPOTAGaps(
        remoteQSOMap: POTARemoteQSOMap,
        container: ModelContainer
    ) async throws -> POTAGapRepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let potaPresence = try fetchPOTAPresenceRecords(context: context)
        var state = GapRepairState()

        for presence in potaPresence {
            try Task.checkCancellation()
            try checkPresenceForGap(presence, remoteQSOMap: remoteQSOMap, state: &state, context: context)
            try checkPresenceForDeadState(presence, remoteQSOMap: remoteQSOMap, state: &state, context: context)
        }

        if state.unsavedCount > 0 {
            try context.save()
        }

        return POTAGapRepairResult(
            activationsChecked: state.activationsChecked.count,
            gapsFound: state.gapsFound,
            deadStateRecovered: state.deadStateRecovered
        )
    }

    // MARK: - Private Helpers

    /// Check a single presence record against the remote map and flag gaps.
    private func checkPresenceForGap(
        _ presence: ServicePresence,
        remoteQSOMap: POTARemoteQSOMap,
        state: inout GapRepairState,
        context: ModelContext
    ) throws {
        guard let qso = presence.qso, isEligibleForGapRepair(presence, qso: qso) else {
            return
        }

        let parks = parksForGapRepair(presence, qso: qso)
        for park in parks {
            let activationKey = buildActivationKey(
                parkRef: park, callsign: qso.myCallsign, timestamp: qso.timestamp
            )
            guard let remoteSet = remoteQSOMap[activationKey], !remoteSet.isEmpty else {
                continue
            }

            state.activationsChecked.insert(activationKey)

            let localDedupKey = buildLocalDedupKey(qso)
            if !remoteSet.contains(localDedupKey) {
                // Log the mismatch for diagnostics (first 10 gaps only)
                if state.gapsFound < 10 {
                    let closest = findClosestRemoteKey(localDedupKey, in: remoteSet)
                    print("[POTA GapRepair] Gap: local=\(localDedupKey) "
                        + "closest=\(closest ?? "none") "
                        + "activation=\(activationKey) "
                        + "remoteCount=\(remoteSet.count)")
                }
                presence.isPresent = false
                presence.needsUpload = true
                state.gapsFound += 1
                state.unsavedCount += 1

                if state.unsavedCount >= 100 {
                    try context.save()
                    state.unsavedCount = 0
                }
            }
        }
    }

    /// Check a single dead-state presence record against the remote map and recover.
    private func checkPresenceForDeadState(
        _ presence: ServicePresence,
        remoteQSOMap: POTARemoteQSOMap,
        state: inout GapRepairState,
        context: ModelContext
    ) throws {
        guard let qso = presence.qso, isEligibleForDeadStateRecovery(presence, qso: qso) else {
            return
        }

        let parks = parksForGapRepair(presence, qso: qso)
        for park in parks {
            let activationKey = buildActivationKey(
                parkRef: park, callsign: qso.myCallsign, timestamp: qso.timestamp
            )
            guard let remoteSet = remoteQSOMap[activationKey], !remoteSet.isEmpty else {
                continue
            }

            state.activationsChecked.insert(activationKey)

            let localDedupKey = buildLocalDedupKey(qso)
            if remoteSet.contains(localDedupKey) {
                presence.isPresent = true
                presence.needsUpload = false
                presence.lastConfirmedAt = Date()
                state.deadStateRecovered += 1
                state.unsavedCount += 1

                if state.unsavedCount >= 100 {
                    try context.save()
                    state.unsavedCount = 0
                }
            }
        }
    }

    /// Whether a presence record is eligible for gap repair checking (isPresent=true).
    private func isEligibleForGapRepair(_ presence: ServicePresence, qso: QSO) -> Bool {
        guard presence.isPresent, !qso.isHidden, !presence.uploadRejected else {
            return false
        }
        // Skip QSOs previously confirmed present — dedup key format differences
        // between local and POTA cause false-positive gaps that trigger re-upload loops.
        if presence.lastConfirmedAt != nil {
            return false
        }
        guard !Self.gapRepairMetadataModes.contains(qso.mode.uppercased()) else {
            return false
        }
        guard qso.importSource != .pota else {
            return false
        }
        let parks = parksForGapRepair(presence, qso: qso)
        return !parks.isEmpty
    }

    /// Whether a presence record is in dead state and eligible for recovery.
    /// Dead state: isPresent=false, needsUpload=false, isSubmitted=false, uploadRejected=false.
    private func isEligibleForDeadStateRecovery(_ presence: ServicePresence, qso: QSO) -> Bool {
        guard !presence.isPresent, !presence.needsUpload,
              !presence.isSubmitted, !presence.uploadRejected
        else {
            return false
        }
        guard !qso.isHidden else {
            return false
        }
        guard !Self.gapRepairMetadataModes.contains(qso.mode.uppercased()) else {
            return false
        }
        guard qso.importSource != .pota else {
            return false
        }
        let parks = parksForGapRepair(presence, qso: qso)
        return !parks.isEmpty
    }

    /// Determine which park references to check for a presence record (gap repair).
    private func parksForGapRepair(_ presence: ServicePresence, qso: QSO) -> [String] {
        if let presencePark = presence.parkReference, !presencePark.isEmpty {
            return [presencePark.uppercased()]
        }
        if let qsoPark = qso.parkReference, !qsoPark.isEmpty {
            return ParkReference.split(qsoPark)
        }
        return []
    }

    /// Build a dedup key from a local QSO for comparison against the remote set.
    /// Format: "WORKEDCALL|BAND|MODE|HHMM" where HHMM is 2-minute bucketed.
    /// Mode is normalized to match POTA's convention (USB/LSB/FM/AM → SSB).
    private func buildLocalDedupKey(_ qso: QSO) -> String {
        let call = qso.callsign.uppercased().trimmingCharacters(in: .whitespaces)
        let band = qso.band.uppercased().trimmingCharacters(in: .whitespaces)
        let mode = POTAClient.normalizeModeForDedup(qso.mode)
        let time = bucketTime(qso.timestamp)
        return "\(call)|\(band)|\(mode)|\(time)"
    }

    /// Bucket a timestamp to 2-minute resolution (round down to even minutes).
    /// Returns "HHMM" in UTC.
    private func bucketTime(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(in: utc, from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let bucketed = minute - (minute % 2)
        return String(format: "%02d%02d", hour, bucketed)
    }

    /// Find the closest matching remote dedup key for diagnostics.
    /// Matches on callsign prefix to find the most relevant comparison.
    private func findClosestRemoteKey(_ localKey: String, in remoteSet: Set<String>) -> String? {
        let localCall = localKey.split(separator: "|").first.map(String.init) ?? ""
        return remoteSet.first { $0.hasPrefix(localCall + "|") }
    }
}
