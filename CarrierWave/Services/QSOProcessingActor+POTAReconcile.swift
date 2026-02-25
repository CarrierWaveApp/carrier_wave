import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - POTA Presence Reconciliation

extension QSOProcessingActor {
    /// Maximum age for a pending/processing job before it's considered stale.
    /// Jobs older than this are reset to needsUpload so they get re-uploaded.
    static let staleJobThreshold: TimeInterval = 30 * 60 // 30 minutes

    struct POTAReconcileResult: Sendable {
        let confirmedCount: Int
        let failedResetCount: Int
        let orphanResetCount: Int
        let inProgressCount: Int
        let staleResetCount: Int
    }

    /// Reconcile POTA ServicePresence records in isSubmitted state against upload jobs.
    /// Jobs are only used for isSubmitted→isPresent transitions:
    /// - isSubmitted + confirmed job → promote to isPresent
    /// - isSubmitted + failed job → reset to needsUpload
    /// - isSubmitted + in-progress job → leave alone (or reset if stale >30min)
    /// - isSubmitted + no matching job → reset to needsUpload (orphan)
    /// Whether isPresent records are actually on POTA is verified by remote map gap repair.
    func reconcilePOTAPresence(
        activationKeys: SyncService.POTAActivationKeys,
        container: ModelContainer
    ) async throws -> POTAReconcileResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let potaPresence = try fetchPOTAPresenceRecords(context: context)

        var counts = ReconcileCounts()

        for (index, presence) in potaPresence.enumerated() {
            try Task.checkCancellation()
            reconcilePresenceRecord(presence, keys: activationKeys, counts: &counts)
            if index.isMultiple(of: 500) {
                await Task.yield()
            }
        }

        if counts.hasChanges {
            try context.save()
        }

        return POTAReconcileResult(
            confirmedCount: counts.confirmed,
            failedResetCount: counts.failedReset, orphanResetCount: counts.orphanReset,
            inProgressCount: counts.inProgress, staleResetCount: counts.staleReset
        )
    }
}

// MARK: - Private Helpers

extension QSOProcessingActor {
    struct ReconcileCounts {
        var confirmed = 0
        var failedReset = 0
        var orphanReset = 0
        var inProgress = 0
        var staleReset = 0

        var hasChanges: Bool {
            confirmed > 0 || failedReset > 0 || orphanReset > 0 || staleReset > 0
        }
    }

    func fetchPOTAPresenceRecords(context: ModelContext) throws -> [ServicePresence] {
        let descriptor = FetchDescriptor<ServicePresence>()
        let allPresence = try context.fetch(descriptor)
        return allPresence.filter { $0.serviceType == .pota }
    }

    private func reconcilePresenceRecord(
        _ presence: ServicePresence,
        keys: SyncService.POTAActivationKeys,
        counts: inout ReconcileCounts
    ) {
        // Only reconcile isSubmitted records — job log tracks upload status
        guard presence.isSubmitted else {
            return
        }
        guard let qso = presence.qso else {
            return
        }
        // Skip hidden (soft-deleted) QSOs — they should never be uploaded
        guard !qso.isHidden else {
            return
        }
        guard qso.importSource != .pota else {
            return
        }
        guard !presence.uploadRejected else {
            return
        }

        let parks = parksForPresence(presence, qso: qso)
        guard !parks.isEmpty else {
            return
        }

        for park in parks {
            let key = buildActivationKey(
                parkRef: park, callsign: qso.myCallsign, timestamp: qso.timestamp
            )
            let normalizedCall = POTAClient.normalizeCallsign(qso.myCallsign)
            let parkCallsignKey =
                "\(park.uppercased())|\(normalizedCall)"
            if reconcileSubmitted(
                presence: presence, key: key, parkCallsignKey: parkCallsignKey,
                keys: keys, counts: &counts
            ) {
                return
            }
        }
    }

    /// Determine which park references to check for a presence record.
    private func parksForPresence(_ presence: ServicePresence, qso: QSO) -> [String] {
        if let presencePark = presence.parkReference, !presencePark.isEmpty {
            return [presencePark.uppercased()]
        }
        if let qsoPark = qso.parkReference, !qsoPark.isEmpty {
            return ParkReference.split(qsoPark)
        }
        return []
    }

    /// Reconcile a submitted presence record against POTA job log.
    private func reconcileSubmitted(
        presence: ServicePresence,
        key: String,
        parkCallsignKey: String,
        keys: SyncService.POTAActivationKeys,
        counts: inout ReconcileCounts
    ) -> Bool {
        if keys.confirmed.contains(key)
            || keys.nilDateConfirmed.contains(parkCallsignKey)
        {
            presence.isPresent = true
            presence.isSubmitted = false
            presence.lastConfirmedAt = Date()
            counts.confirmed += 1
        } else if keys.failed.contains(key)
            || keys.nilDateFailed.contains(parkCallsignKey)
        {
            presence.isSubmitted = false
            presence.needsUpload = true
            counts.failedReset += 1
        } else if let submittedAt = keys.inProgress[key] {
            let age = Date().timeIntervalSince(submittedAt)
            if age >= Self.staleJobThreshold {
                presence.isSubmitted = false
                presence.needsUpload = true
                counts.staleReset += 1
            } else {
                counts.inProgress += 1
            }
        } else if presence.lastConfirmedAt != nil {
            // No matching job, but QSO was previously confirmed on POTA.
            // The job aged out of the POTA log — promote back to isPresent
            // rather than re-uploading (which creates a duplicate).
            presence.isSubmitted = false
            presence.isPresent = true
            presence.lastConfirmedAt = Date()
            counts.confirmed += 1
        } else {
            // No matching job and never confirmed — POTA likely silently dropped it.
            presence.isSubmitted = false
            presence.needsUpload = true
            counts.orphanReset += 1
        }
        return true
    }

    /// Build an activation key for matching against POTA jobs.
    /// Format: "PARKREF|CALLSIGN|YYYY-MM-DD"
    /// Callsign is normalized to strip portable suffixes (/P, /M, etc.)
    /// so local and remote keys match regardless of suffix usage.
    func buildActivationKey(parkRef: String, callsign: String, timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = formatter.string(from: timestamp)
        let normalizedCall = POTAClient.normalizeCallsign(callsign)
        return "\(parkRef.uppercased())|\(normalizedCall)|\(dateStr)"
    }
}
