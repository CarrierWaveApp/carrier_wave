import CarrierWaveData
import SwiftUI
import UIKit

// MARK: - ShareCardRenderer

/// Renders ShareCardView to UIImage for sharing
@MainActor
enum ShareCardRenderer {
    // MARK: Internal

    /// Render a share card to a UIImage
    static func render(content: ShareCardContent) -> UIImage? {
        let view = ShareCardView(content: content)
        return renderToImage(view)
    }

    /// Render an activity item to a shareable image
    static func render(activityItem: ActivityItem) -> UIImage? {
        let content = ShareCardContent.forActivityItem(activityItem)
        return render(content: content)
    }

    /// Render a summary card to a shareable image
    static func renderSummary(_ summary: SummaryCardData) -> UIImage? {
        let content = ShareCardContent.forSummary(summary)
        return render(content: content)
    }

    // MARK: Private

    private static func renderToImage(_ view: some View) -> UIImage? {
        let controller = UIHostingController(rootView: view)
        let targetSize = CGSize(width: 400, height: 500)

        controller.view.bounds = CGRect(origin: .zero, size: targetSize)
        controller.view.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - ShareHelper

/// Helper for sharing via iOS share sheet
@MainActor
enum ShareHelper {
    // MARK: Internal

    /// Present the share sheet for an activity item
    static func shareActivityItem(_ item: ActivityItem, from viewController: UIViewController?) {
        guard let image = ShareCardRenderer.render(activityItem: item) else {
            return
        }

        presentShareSheet(with: [image], from: viewController)
    }

    /// Present the share sheet for a summary card
    static func shareSummary(_ summary: SummaryCardData, from viewController: UIViewController?) {
        guard let image = ShareCardRenderer.renderSummary(summary) else {
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
                x: (presenter?.view.bounds.midX ?? 0),
                y: (presenter?.view.bounds.midY ?? 0),
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

// MARK: - ShareableActivityItem

/// A view modifier that adds share functionality
struct ShareableActivityItem: ViewModifier {
    // MARK: Internal

    let item: ActivityItem

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingShareSheet) {
                ShareSheetView(item: item)
            }
            .environment(\.shareAction) {
                showingShareSheet = true
            }
    }

    // MARK: Private

    @State private var showingShareSheet = false
}

// MARK: - ShareSheetView

/// SwiftUI wrapper for presenting share sheet
struct ShareSheetView: UIViewControllerRepresentable {
    let item: ActivityItem

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let image = ShareCardRenderer.render(activityItem: item) ?? UIImage()
        return UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

// MARK: - ShareActionKey

private struct ShareActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var shareAction: () -> Void {
        get { self[ShareActionKey.self] }
        set { self[ShareActionKey.self] = newValue }
    }
}
