// Replace POTA Upload
//
// Deletes an activation's log from POTA (allowed for 24 hours after the
// upload) and uploads the QSOs again as they are now. Shared by the two
// screens that host SessionDetailView for an activation.

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - POTAReplaceUpload

@MainActor
private enum POTAReplaceUpload {
    /// Remove the uploaded jobs, then mark every QSO as needing upload again.
    /// Returns an error keyed by park reference if POTA refused; in that case
    /// nothing local is changed, so the log on POTA and the app still agree.
    static func removeAndReset(
        _ activation: POTAActivation,
        plan: POTAUploadReplacePlan,
        client: POTAClient?,
        context: ModelContext
    ) async -> [String: String]? {
        guard let client else {
            return [activation.parkReference: "POTA client not available"]
        }
        let debugLog = SyncDebugLog.shared
        debugLog.info(
            "replaceUpload: removing \(plan.removeJobIds.count) job(s) for "
                + activation.parkReference,
            service: .pota
        )
        do {
            try await client.removeJobs(in: plan)
        } catch {
            debugLog.error(
                "replaceUpload: removal failed for \(activation.parkReference): "
                    + error.localizedDescription,
                service: .pota
            )
            return [activation.parkReference: error.localizedDescription]
        }

        for qso in activation.qsos {
            for park in activation.parks {
                qso.forceResetParkUpload(park, context: context)
            }
        }
        try? context.save()
        return nil
    }
}

// MARK: - POTAActivationsContentView

extension POTAActivationsContentView {
    func replaceUpload(
        _ activation: POTAActivation, plan: POTAUploadReplacePlan
    ) async -> [String: String] {
        if let errors = await POTAReplaceUpload.removeAndReset(
            activation, plan: plan, client: potaClient, context: modelContext
        ) {
            return errors
        }
        await loadParkQSOs()
        let fresh = rebuildActivation(matching: activation) ?? activation
        let errors = await performUploadReturningErrors(for: fresh)
        await loadParkQSOs()
        return errors
    }
}

// MARK: - SessionsView

extension SessionsView {
    func replaceUpload(
        _ activation: POTAActivation, plan: POTAUploadReplacePlan
    ) async -> [String: String] {
        if let errors = await POTAReplaceUpload.removeAndReset(
            activation, plan: plan, client: potaClient, context: modelContext
        ) {
            return errors
        }
        await loadSessions()
        await loadOrphanActivations()
        var errors: [String: String] = [:]
        if let fresh = allActivations.first(where: { $0.id == activation.id }) {
            errors = await performUploadReturningErrors(for: fresh)
        } else {
            await refreshJobs()
        }
        await loadSessions()
        await loadOrphanActivations()
        return errors
    }
}
