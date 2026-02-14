// POTA Activations View - Share Actions

import SwiftUI

extension POTAActivationsContentView {
    func generateAndShare(activation: POTAActivation) async {
        isGeneratingShareImage = true
        activationToShare = nil

        let image = await ActivationShareRenderer.renderWithMap(
            activation: activation,
            parkName: parkName(for: activation.parkReference),
            myGrid: activation.qsos.first?.myGrid,
            metadata: metadata(for: activation)
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
