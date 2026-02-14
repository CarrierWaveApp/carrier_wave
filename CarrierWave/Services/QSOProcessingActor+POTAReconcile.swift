import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - POTA Presence Reconciliation

extension QSOProcessingActor {
    /// Maximum age for a pending/processing job before it's considered stale.
    /// Jobs older than this are reset to needsUpload so they get re-uploaded.
    static let staleJobThreshold: TimeInterval = 30 * 60 // 30 minutes

    struct POTAReconcileResult: Sendable {
        let resetCount: Int
        let confirmedCount: Int
        let failedResetCount: Int
        let orphanResetCount: Int
        let inProgressCount: Int
        let staleResetCount: Int
    }

    /// Reconcile POTA ServicePresence records against completed upload jobs.
    /// If a QSO's POTA presence says isPresent=true but no completed job covers
    /// that activation (park + callsign + UTC date), reset it to needsUpload=true.
    /// Also confirms submitted QSOs that have a completed job, resets submitted
    /// QSOs whose jobs failed, leaves recent in-progress jobs alone, and resets
    /// stale in-progress jobs (pending/processing >30 min).
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
            resetCount: counts.reset, confirmedCount: counts.confirmed,
            failedResetCount: counts.failedReset, orphanResetCount: counts.orphanReset,
            inProgressCount: counts.inProgress, staleResetCount: counts.staleReset
        )
    }
}

// MARK: - Private Helpers

extension QSOProcessingActor {
    struct ReconcileCounts {
        var reset = 0
        var confirmed = 0
        var failedReset = 0
        var orphanReset = 0
        var inProgress = 0
        var staleReset = 0

        var hasChanges: Bool {
            reset > 0 || confirmed > 0 || failedReset > 0 || orphanReset > 0
                || staleReset > 0
        }
    }

    private func fetchPOTAPresenceRecords(context: ModelContext) throws -> [ServicePresence] {
        let descriptor = FetchDescriptor<ServicePresence>()
        let allPresence = try context.fetch(descriptor)
        return allPresence.filter { $0.serviceType == .pota }
    }

    private func reconcilePresenceRecord(
        _ presence: ServicePresence,
        keys: SyncService.POTAActivationKeys,
        counts: inout ReconcileCounts
    ) {
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
            if applyReconciliation(presence: presence, key: key, keys: keys, counts: &counts) {
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

    /// Apply reconciliation logic for a single (presence, key) pair.
    /// Returns true if the presence was handled and no further parks need checking.
    @discardableResult
    private func applyReconciliation(
        presence: ServicePresence,
        key: String,
        keys: SyncService.POTAActivationKeys,
        counts: inout ReconcileCounts
    ) -> Bool {
        if presence.isPresent {
            if !keys.confirmed.contains(key) {
                presence.isPresent = false
                presence.needsUpload = true
                counts.reset += 1
                return true
            }
        } else if presence.isSubmitted {
            if keys.confirmed.contains(key) {
                presence.isPresent = true
                presence.isSubmitted = false
                presence.lastConfirmedAt = Date()
                counts.confirmed += 1
                return true
            } else if keys.failed.contains(key) {
                presence.isSubmitted = false
                presence.needsUpload = true
                counts.failedReset += 1
                return true
            } else if let submittedAt = keys.inProgress[key] {
                let age = Date().timeIntervalSince(submittedAt)
                if age >= Self.staleJobThreshold {
                    // Job has been pending/processing too long — reset to retry.
                    presence.isSubmitted = false
                    presence.needsUpload = true
                    counts.staleReset += 1
                } else {
                    // Job is recent — leave isSubmitted alone, wait for POTA.
                    counts.inProgress += 1
                }
                return true
            } else {
                // Submitted but no matching job at all (confirmed, failed, or in-progress).
                // POTA likely silently dropped the upload — reset to retry.
                presence.isSubmitted = false
                presence.needsUpload = true
                counts.orphanReset += 1
                return true
            }
        }
        return false
    }

    /// Build an activation key for matching against POTA jobs.
    /// Format: "PARKREF|CALLSIGN|YYYY-MM-DD"
    func buildActivationKey(parkRef: String, callsign: String, timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = formatter.string(from: timestamp)
        return "\(parkRef.uppercased())|\(callsign.uppercased())|\(dateStr)"
    }
}
