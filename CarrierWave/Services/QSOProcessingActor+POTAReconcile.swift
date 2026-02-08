import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - POTA Presence Reconciliation

extension QSOProcessingActor {
    struct POTAReconcileResult: Sendable {
        let resetCount: Int
        let confirmedCount: Int
        let failedResetCount: Int
        let orphanResetCount: Int
    }

    /// Reconcile POTA ServicePresence records against completed upload jobs.
    /// If a QSO's POTA presence says isPresent=true but no completed job covers
    /// that activation (park + callsign + UTC date), reset it to needsUpload=true.
    /// Also confirms submitted QSOs that have a completed job and resets submitted
    /// QSOs whose jobs failed.
    func reconcilePOTAPresence(
        confirmedActivationKeys: Set<String>,
        failedActivationKeys: Set<String>,
        container: ModelContainer
    ) async throws -> POTAReconcileResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let potaPresence = try fetchPOTAPresenceRecords(context: context)

        var counts = ReconcileCounts()

        for (index, presence) in potaPresence.enumerated() {
            try Task.checkCancellation()
            reconcilePresenceRecord(
                presence,
                confirmedKeys: confirmedActivationKeys,
                failedKeys: failedActivationKeys,
                counts: &counts
            )
            if index.isMultiple(of: 500) {
                await Task.yield()
            }
        }

        if counts.hasChanges {
            try context.save()
        }

        return POTAReconcileResult(
            resetCount: counts.reset, confirmedCount: counts.confirmed,
            failedResetCount: counts.failedReset, orphanResetCount: counts.orphanReset
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

        var hasChanges: Bool {
            reset > 0 || confirmed > 0 || failedReset > 0 || orphanReset > 0
        }
    }

    private func fetchPOTAPresenceRecords(context: ModelContext) throws -> [ServicePresence] {
        let descriptor = FetchDescriptor<ServicePresence>()
        let allPresence = try context.fetch(descriptor)
        return allPresence.filter { $0.serviceType == .pota }
    }

    private func reconcilePresenceRecord(
        _ presence: ServicePresence,
        confirmedKeys: Set<String>,
        failedKeys: Set<String>,
        counts: inout ReconcileCounts
    ) {
        guard let qso = presence.qso else {
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
            if applyReconciliation(
                presence: presence, key: key,
                confirmedKeys: confirmedKeys, failedKeys: failedKeys,
                counts: &counts
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

    /// Apply reconciliation logic for a single (presence, key) pair.
    /// Returns true if the presence was modified and no further parks need checking.
    @discardableResult
    private func applyReconciliation(
        presence: ServicePresence,
        key: String,
        confirmedKeys: Set<String>,
        failedKeys: Set<String>,
        counts: inout ReconcileCounts
    ) -> Bool {
        if presence.isPresent {
            if !confirmedKeys.contains(key) {
                presence.isPresent = false
                presence.needsUpload = true
                counts.reset += 1
                return true
            }
        } else if presence.isSubmitted {
            if confirmedKeys.contains(key) {
                presence.isPresent = true
                presence.isSubmitted = false
                presence.lastConfirmedAt = Date()
                counts.confirmed += 1
                return true
            } else if failedKeys.contains(key) {
                presence.isSubmitted = false
                presence.needsUpload = true
                counts.failedReset += 1
                return true
            } else {
                // Submitted but no matching job at all (confirmed or failed).
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
