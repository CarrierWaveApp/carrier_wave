// SessionsView Brag Sheet Generation
//
// Extracted from SessionsView+Actions to keep under the 500-line file limit.

import SwiftUI

// MARK: - Brag Sheet Generation

extension SessionsView {
    func generateAndShare(activation: POTAActivation) async {
        isGeneratingShareImage = true
        let meta = activationMetadata(for: activation)
        let name = parkName(for: activation.parkReference)
        let equipmentList = buildEquipmentList(for: activation)

        let statisticianMode = UserDefaults.standard.bool(
            forKey: "statisticianMode"
        )
        let advancedStats: ActivationStatistics? =
            if statisticianMode {
                ActivationStatistics.compute(from: activation, metadata: meta)
            } else {
                nil
            }

        if let image = await ActivationShareRenderer.renderWithMap(
            activation: activation,
            parkName: name,
            myGrid: activation.qsos.first?.myGrid,
            metadata: meta,
            equipment: equipmentList,
            statisticianStats: advancedStats
        ) {
            sharePreviewData = SharePreviewData(
                image: image,
                activation: activation,
                parkName: name
            )
        }
        isGeneratingShareImage = false
        activationToShare = nil
    }

    func showMap(session: LoggingSession, activations: [POTAActivation]) {
        if session.isRove, activations.count > 1 {
            roveStopsForMap = session.mergedRoveStops
            activationToMap = mergedRoveActivation(activations)
        } else if let act = activations.first {
            activationToMap = act
        }
    }

    func sessionDetailForActivation(
        _ activation: POTAActivation, session: LoggingSession
    ) -> SessionDetailView {
        let jobs = jobsByActivationId[activation.id] ?? []
        return SessionDetailView(
            session: session,
            onShare: { activationToShare = activation },
            onExport: { activationToExport = activation },
            activation: activation,
            activationMetadata: activationMetadata(for: activation),
            parkName: parkName(for: activation.parkReference),
            matchingJobs: jobs,
            potaClient: potaClient,
            isAuthenticated: isAuthenticated,
            isInMaintenance: isInMaintenance,
            onUpload: {
                await performUploadReturningErrors(for: activation)
            },
            onReject: { activationToReject = activation },
            onForceReupload: { forceReupload(activation) }
        )
    }

    func roveSessionDetail(
        session: LoggingSession, activations: [POTAActivation]
    ) -> SessionDetailView {
        let primary = activations.first
        let merged = activations.count > 1
            ? mergedRoveActivation(activations) : primary
        let jobs = primary.flatMap { jobsByActivationId[$0.id] ?? [] } ?? []
        let meta = primary.flatMap { activationMetadata(for: $0) }

        return SessionDetailView(
            session: session,
            onShare: activations.isEmpty ? nil : {
                if activations.count > 1 {
                    activationToShare = mergedRoveActivation(activations)
                } else if let act = activations.first {
                    activationToShare = act
                }
            },
            onExport: activations.first.map { act in
                { activationToExport = act }
            },
            activation: merged,
            activationMetadata: meta,
            parkName: primary.flatMap {
                parkName(for: $0.parkReference)
            },
            matchingJobs: jobs,
            potaClient: potaClient,
            isAuthenticated: isAuthenticated,
            isInMaintenance: isInMaintenance,
            onUpload: primary.map { act in
                { await performUploadReturningErrors(for: act) }
            },
            onReject: primary.map { act in
                { activationToReject = act }
            },
            onForceReupload: primary.map { act in
                { forceReupload(act) }
            }
        )
    }

    func buildEquipmentList(
        for activation: POTAActivation
    ) -> [ShareCardEquipmentItem] {
        let includeEquipment = UserDefaults.standard.object(
            forKey: "shareCardIncludeEquipment"
        ) as? Bool ?? true
        guard includeEquipment else {
            return []
        }

        guard let session = findSession(for: activation) else {
            return []
        }

        var items: [ShareCardEquipmentItem] = []
        if let antenna = session.myAntenna, !antenna.isEmpty {
            items.append(ShareCardEquipmentItem(
                icon: "antenna.radiowaves.left.and.right", text: antenna
            ))
        }
        if let key = session.myKey, !key.isEmpty {
            items.append(ShareCardEquipmentItem(
                icon: "pianokeys", text: key
            ))
        }
        if let mic = session.myMic, !mic.isEmpty {
            items.append(ShareCardEquipmentItem(
                icon: "mic.fill", text: mic
            ))
        }
        if let extra = session.extraEquipment, !extra.isEmpty {
            items.append(ShareCardEquipmentItem(
                icon: "wrench.and.screwdriver", text: extra
            ))
        }
        return items
    }

    // MARK: - Row Builder Helpers

    func buildUploadHandler(
        activations: [POTAActivation]
    ) -> (() async -> [String: String])? {
        guard !activations.isEmpty else {
            return nil
        }
        return {
            var allErrors: [String: String] = [:]
            for act in activations {
                let errors = await performUploadReturningErrors(for: act)
                allErrors.merge(errors) { _, new in new }
            }
            return allErrors
        }
    }

    func buildShareHandler(
        session: LoggingSession,
        activations: [POTAActivation]
    ) -> (() -> Void)? {
        guard activations.first != nil else {
            return nil
        }
        return {
            if session.isRove, activations.count > 1 {
                activationToShare = mergedRoveActivation(activations)
            } else if let act = activations.first {
                activationToShare = act
            }
        }
    }
}
