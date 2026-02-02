// Activation Share Renderer
//
// Renders ActivationShareCardView to UIImage for sharing.

import SwiftUI
import UIKit

// MARK: - ActivationShareRenderer

/// Renders activation share cards to UIImage for sharing
@MainActor
enum ActivationShareRenderer {
    // MARK: Internal

    /// Render an activation share card to a UIImage
    static func render(
        activation: POTAActivation,
        parkName: String?,
        myGrid: String?
    ) -> UIImage? {
        let view = ActivationShareCardView(
            activation: activation,
            parkName: parkName,
            myGrid: myGrid
        )
        return renderToImage(view)
    }

    // MARK: Private

    private static func renderToImage(_ view: some View) -> UIImage? {
        let controller = UIHostingController(rootView: view)
        let targetSize = CGSize(width: 400, height: 600)

        controller.view.bounds = CGRect(origin: .zero, size: targetSize)
        controller.view.backgroundColor = .clear

        // Force layout pass
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - ActivationShareHelper

/// Helper for sharing activation cards via iOS share sheet
@MainActor
enum ActivationShareHelper {
    // MARK: Internal

    /// Present the share sheet for an activation
    static func shareActivation(
        _ activation: POTAActivation,
        parkName: String?,
        myGrid: String?,
        from viewController: UIViewController?
    ) {
        guard
            let image = ActivationShareRenderer.render(
                activation: activation,
                parkName: parkName,
                myGrid: myGrid
            )
        else {
            return
        }

        presentShareSheet(with: [image], from: viewController)
    }

    // MARK: Private

    /// Present the iOS share sheet with the given items
    private static func presentShareSheet(with items: [Any], from viewController: UIViewController?) {
        let activityViewController = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        // Get the root view controller if none provided
        let presenter = viewController ?? getRootViewController()

        // For iPad, set the popover presentation controller
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = presenter?.view
            popover.sourceRect = CGRect(
                x: presenter?.view.bounds.midX ?? 0,
                y: presenter?.view.bounds.midY ?? 0,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        presenter?.present(activityViewController, animated: true)
    }

    private static func getRootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
        else {
            return nil
        }
        return window.rootViewController
    }
}
