//
//  EnrichedShareButton.swift
//  CarrierWave
//
//  SwiftUI helper that drops a system Share button into any view, wired
//  to an enriched link payload. The button presents a UIActivityViewController
//  with our EnrichedLinkItemProvider, so iMessage / Mail / Notes get the
//  rich LPLinkMetadata card preview.
//

import CarrierWaveCore
import SwiftUI
import UIKit

// MARK: - EnrichedShareButton

struct EnrichedShareButton: View {
    // MARK: Lifecycle

    init(payload: EnrichedLinkPayload, label: String? = nil) {
        self.payload = payload
        self.label = label
    }

    // MARK: Internal

    var body: some View {
        Button {
            present()
        } label: {
            if let label {
                Label(label, systemImage: "square.and.arrow.up")
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .accessibilityLabel("Share")
    }

    // MARK: Private

    private let payload: EnrichedLinkPayload
    private let label: String?

    @MainActor
    private func present() {
        guard let provider = EnrichedLinkItemProvider(payload: payload) else {
            return
        }
        let activityVC = UIActivityViewController(
            activityItems: [provider],
            applicationActivities: nil
        )
        // Find the topmost view controller to present from. We avoid
        // depending on a window environment value because this helper is
        // dropped into many places.
        guard
            let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return
        }
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        // iPad popover anchor — center on the presenter view to avoid the
        // empty-source-rect crash.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(activityVC, animated: true)
    }
}
