// Activation Share Renderer
//
// Renders ActivationShareCardView to UIImage for sharing.

import MapKit
import SwiftUI
import UIKit

// MARK: - ShareMapMarker

/// Lightweight marker for share card map rendering with RST-based color
struct ShareMapMarker: Sendable {
    let coordinate: CLLocationCoordinate2D
    let rstColor: UIColor
}

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
        metadata: ActivationMetadata? = nil,
        equipment: [ShareCardEquipmentItem] = [],
        statisticianStats: ActivationStatistics? = nil
    ) -> UIImage? {
        let view = ActivationShareCardForExport(
            activation: activation,
            parkName: parkName,
            mapImage: nil,
            metadata: metadata,
            equipment: equipment,
            statisticianStats: statisticianStats
        )
        let height: CGFloat = statisticianStats != nil ? 880 : 640
        return renderToImage(view, height: height)
    }

    /// Render an activation share card with map snapshot (async)
    static func renderWithMap(
        activation: POTAActivation,
        parkName: String?,
        myGrid: String?,
        metadata: ActivationMetadata? = nil,
        equipment: [ShareCardEquipmentItem] = [],
        statisticianStats: ActivationStatistics? = nil
    ) async -> UIImage? {
        let (qsoMarkers, myCoordinate) = await computeMapMarkers(
            activation: activation, myGrid: myGrid
        )

        // Generate map snapshot if we have coordinates
        let mapImage: UIImage? =
            if !qsoMarkers.isEmpty {
                await generateMapSnapshot(
                    markers: qsoMarkers,
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
                metadata: metadata,
                equipment: equipment,
                statisticianStats: statisticianStats
            )
            let height: CGFloat = statisticianStats != nil ? 880 : 640
            return renderToImage(view, height: height)
        }
    }

    // MARK: Private

    /// Extract QSO marker data and compute coordinates off the main thread
    private static func computeMapMarkers(
        activation: POTAActivation,
        myGrid: String?
    ) async -> ([ShareMapMarker], CLLocationCoordinate2D?) {
        let qsoData: [(grid: String, rstColor: UIColor)] =
            activation.mappableQSOs.compactMap { qso in
                guard let grid = qso.theirGrid else {
                    return nil
                }
                return (
                    grid,
                    RSTColorHelper.uiColor(
                        rstSent: qso.rstSent,
                        rstReceived: qso.rstReceived
                    )
                )
            }
        let capturedMyGrid = myGrid

        await Task.yield()

        return await Task.detached {
            let markers: [ShareMapMarker] = qsoData.compactMap { item in
                guard let coord = MaidenheadConverter.coordinate(from: item.grid) else {
                    return nil
                }
                return ShareMapMarker(coordinate: coord, rstColor: item.rstColor)
            }
            let myCoord: CLLocationCoordinate2D? =
                if let grid = capturedMyGrid, grid.count >= 4 {
                    MaidenheadConverter.coordinate(from: grid)
                } else {
                    nil
                }
            return (markers, myCoord)
        }.value
    }

    @MainActor
    private static func renderToImage(
        _ view: some View, height: CGFloat = 640
    ) -> UIImage? {
        let wrappedView = view.frame(width: 400, height: height)

        let renderer = ImageRenderer(content: wrappedView)
        renderer.scale = 2.0 // Retina scale for crisp edges
        renderer.isOpaque = true // Square corners, no transparency needed
        return renderer.uiImage
    }

    private static func generateMapSnapshot(
        markers: [ShareMapMarker],
        myCoordinate: CLLocationCoordinate2D?
    ) async -> UIImage? {
        guard
            let region = ActivationMapHelpers.mapRegion(
                qsoCoordinates: markers.map(\.coordinate),
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
            return drawAnnotations(
                on: snapshot,
                markers: markers,
                myCoordinate: myCoordinate
            )
        } catch {
            return nil
        }
    }

    private static func drawAnnotations(
        on snapshot: MKMapSnapshotter.Snapshot,
        markers: [ShareMapMarker],
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

            for marker in markers {
                let path = ActivationMapHelpers.geodesicPath(
                    from: myCoord, to: marker.coordinate, segments: 30
                )
                guard path.count >= 2 else {
                    continue
                }

                context.move(to: snapshot.point(for: path[0]))
                for i in 1 ..< path.count {
                    context.addLine(to: snapshot.point(for: path[i]))
                }
                context.strokePath()
            }
        }

        // Draw QSO markers with RST-based colors
        for marker in markers {
            let point = snapshot.point(for: marker.coordinate)
            drawMarker(at: point, in: context, color: marker.rstColor)
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
