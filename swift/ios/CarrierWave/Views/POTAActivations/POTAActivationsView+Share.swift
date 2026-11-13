// POTA Activations View - Share Actions

import CarrierWaveData
import SwiftUI

extension POTAActivationsContentView {
    func generateAndShare(activation: POTAActivation) async {
        isGeneratingShareImage = true
        activationToShare = nil

        // Repair missing grids before rendering the share card
        let lookupService = CallsignLookupService(modelContext: modelContext)
        await lookupService.repairMissingGrids(
            for: activation.qsos, in: modelContext
        )

        let statisticianMode = UserDefaults.standard.bool(
            forKey: "statisticianMode"
        )
        let advancedStats: ActivationStatistics? =
            if statisticianMode {
                ActivationStatistics.compute(
                    from: activation,
                    metadata: metadata(for: activation)
                )
            } else {
                nil
            }

        let myGrid = resolveMyGrid(for: activation)
        let activationMetadata = metadata(for: activation)
        let name = parkName(for: activation.parkReference)

        // Reused by the preview sheet to re-render from the live QSO
        // records once offline lookups eventually complete.
        let render: @MainActor () async -> UIImage? = {
            await ActivationShareRenderer.renderWithMap(
                source: .pota(activation: activation, parkName: name),
                myGrid: myGrid,
                metadata: activationMetadata,
                statisticianStats: advancedStats
            )
        }

        let image = await render()

        isGeneratingShareImage = false

        guard let image else {
            return
        }

        sharePreviewData = SharePreviewData(
            image: image,
            activation: activation,
            parkName: name,
            qsos: activation.qsos,
            rerender: render
        )
    }

    /// Resolve myGrid for the share card map, with optional park fallback.
    private func resolveMyGrid(for activation: POTAActivation) -> String? {
        // Primary: grid from the QSOs themselves
        if let grid = activation.qsos.first?.myGrid, !grid.isEmpty {
            return grid
        }

        // Fallback: use park's grid if the setting is enabled
        let useParkFallback = UserDefaults.standard.bool(
            forKey: "useParkGridForShareCard"
        )
        guard useParkFallback else {
            return nil
        }

        return POTAParksCache.shared.parkSync(
            for: activation.parkReference
        )?.grid
    }
}
