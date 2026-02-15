// POTA Activations View - Share Actions

import SwiftUI

extension POTAActivationsContentView {
    func generateAndShare(activation: POTAActivation) async {
        isGeneratingShareImage = true
        activationToShare = nil

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

        let image = await ActivationShareRenderer.renderWithMap(
            activation: activation,
            parkName: parkName(for: activation.parkReference),
            myGrid: activation.qsos.first?.myGrid,
            metadata: metadata(for: activation),
            statisticianStats: advancedStats
        )

        isGeneratingShareImage = false

        guard let image else {
            return
        }

        sharePreviewData = SharePreviewData(
            image: image,
            activation: activation,
            parkName: parkName(for: activation.parkReference)
        )
    }
}
