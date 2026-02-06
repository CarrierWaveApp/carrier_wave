// Activation Share Renderer
//
// Renders ActivationShareCardView to UIImage for sharing.

import MapKit
import SwiftUI
import UIKit

// MARK: - ActivationShareRenderer

/// Renders activation share cards to UIImage for sharing
@MainActor
enum ActivationShareRenderer {
    // MARK: Internal

    /// Render an activation share card to a UIImage (synchronous, no map)
    static func render(
        activation: POTAActivation,
        parkName: String?,
        myGrid: String?,
        metadata: ActivationMetadata? = nil
    ) -> UIImage? {
        // For synchronous rendering, use nil map (will show placeholder)
        let view = ActivationShareCardForExport(
            activation: activation,
            parkName: parkName,
            mapImage: nil,
            metadata: metadata
        )
        return renderToImage(view)
    }

    /// Render an activation share card with map snapshot (async)
    static func renderWithMap(
        activation: POTAActivation,
        parkName: String?,
        myGrid: String?,
        metadata: ActivationMetadata? = nil
    ) async -> UIImage? {
        // Capture minimal data on main thread, then yield immediately
        let qsoGrids: [(id: UUID, grid: String)] = activation.mappableQSOs.compactMap { qso in
            guard let grid = qso.theirGrid else {
                return nil
            }
            return (qso.id, grid)
        }
        let capturedMyGrid = myGrid

        // Yield to let UI update (show spinner) before heavy computation
        await Task.yield()

        // Compute coordinates off main thread
        let (qsoCoordinates, myCoordinate) = await Task.detached {
            let coords: [CLLocationCoordinate2D] = qsoGrids.compactMap { item in
                MaidenheadConverter.coordinate(from: item.grid)
            }

            let myCoord: CLLocationCoordinate2D? =
                if let grid = capturedMyGrid, grid.count >= 4 {
                    MaidenheadConverter.coordinate(from: grid)
                } else {
                    nil
                }

            return (coords, myCoord)
        }.value

        // Generate map snapshot if we have coordinates
        let mapImage: UIImage? =
            if !qsoCoordinates.isEmpty {
                await generateMapSnapshot(
                    qsoCoordinates: qsoCoordinates,
                    myCoordinate: myCoordinate
                )
            } else {
                nil
            }

        // Render the card with the map image (must be on main thread)
        return await MainActor.run {
            let view = ActivationShareCardForExport(
                activation: activation,
                parkName: parkName,
                mapImage: mapImage,
                metadata: metadata
            )
            return renderToImage(view)
        }
    }

    // MARK: Private

    @MainActor
    private static func renderToImage(_ view: some View) -> UIImage? {
        // Wrap in ZStack with clear background to ensure transparency
        let transparentView = ZStack {
            Color.clear
            view
        }
        .frame(width: 400, height: 600)

        let renderer = ImageRenderer(content: transparentView)
        renderer.scale = 2.0 // Retina scale for crisp edges
        renderer.isOpaque = false // Preserve transparency for rounded corners
        return renderer.uiImage
    }

    private static func generateMapSnapshot(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) async -> UIImage? {
        guard
            let region = ActivationMapHelpers.mapRegion(
                qsoCoordinates: qsoCoordinates,
                myCoordinate: myCoordinate
            )
        else {
            return nil
        }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 368, height: 200) // Card width minus padding
        options.mapType = .standard
        options.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()

            // Draw annotations on the snapshot
            return drawAnnotations(
                on: snapshot,
                qsoCoordinates: qsoCoordinates,
                myCoordinate: myCoordinate
            )
        } catch {
            return nil
        }
    }

    private static func drawAnnotations(
        on snapshot: MKMapSnapshotter.Snapshot,
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> UIImage {
        let image = snapshot.image

        UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
        image.draw(at: .zero)

        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return image
        }

        // Draw geodesic paths from my location to each QSO
        if let myCoord = myCoordinate {
            context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(2.0)

            for qsoCoord in qsoCoordinates {
                let path = ActivationMapHelpers.geodesicPath(
                    from: myCoord, to: qsoCoord, segments: 30
                )
                guard path.count >= 2 else {
                    continue
                }

                let startPoint = snapshot.point(for: path[0])
                context.move(to: startPoint)

                for i in 1 ..< path.count {
                    let point = snapshot.point(for: path[i])
                    context.addLine(to: point)
                }
                context.strokePath()
            }
        }

        // Draw QSO markers
        for coord in qsoCoordinates {
            let point = snapshot.point(for: coord)
            drawMarker(at: point, in: context, color: .systemGreen)
        }

        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return finalImage ?? image
    }

    private static func drawMarker(at point: CGPoint, in context: CGContext, color: UIColor) {
        let markerSize: CGFloat = 12

        // White background circle
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(
            in: CGRect(
                x: point.x - markerSize / 2 - 2,
                y: point.y - markerSize / 2 - 2,
                width: markerSize + 4,
                height: markerSize + 4
            )
        )

        // Colored marker
        context.setFillColor(color.cgColor)
        context.fillEllipse(
            in: CGRect(
                x: point.x - markerSize / 2,
                y: point.y - markerSize / 2,
                width: markerSize,
                height: markerSize
            )
        )
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
