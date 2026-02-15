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
    }

    /// Mutable state accumulated during gap repair iteration.
    private struct GapRepairState {
        var activationsChecked = Set<String>()
        var gapsFound = 0
        var unsavedCount = 0
    }

    /// Compare local POTA QSOs against what POTA's API returned per-activation.
    /// If a local QSO claims isPresent=true but isn't in the remote set for its
    /// activation, reset it to needsUpload=true so it gets re-uploaded.
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
        }

        if state.unsavedCount > 0 {
            try context.save()
        }

        return POTAGapRepairResult(
            activationsChecked: state.activationsChecked.count,
            gapsFound: state.gapsFound
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

    /// Whether a presence record is eligible for gap repair checking.
    private func isEligibleForGapRepair(_ presence: ServicePresence, qso: QSO) -> Bool {
        guard presence.isPresent, !qso.isHidden, !presence.uploadRejected else {
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
    private func buildLocalDedupKey(_ qso: QSO) -> String {
        let call = qso.callsign.uppercased().trimmingCharacters(in: .whitespaces)
        let band = qso.band.uppercased().trimmingCharacters(in: .whitespaces)
        let mode = qso.mode.uppercased().trimmingCharacters(in: .whitespaces)
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
}
