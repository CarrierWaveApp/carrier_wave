// Activation Share Renderer
//
// Renders ActivationShareCardView to UIImage for sharing.
//
// The map section is resolved at render time from the current QSO records
// (grid → their park → their summit → DXCC centroid) and never blocks on
// connectivity: when MKMapSnapshotter fails or times out the card falls back
// to `ActivationShareOfflineMap`, a deterministic vector render at the same
// size, so the brag sheet can always be saved or shared in the field.

import CarrierWaveData
import MapKit
import SwiftUI
import UIKit

// MARK: - ShareMapMarker

/// Lightweight marker for share card map rendering with RST-based color
nonisolated struct ShareMapMarker: Sendable {
    let coordinate: CLLocationCoordinate2D
    let rstColor: UIColor
}

// MARK: - ActivationShareRenderer

/// Renders activation share cards to UIImage for sharing
@MainActor
enum ActivationShareRenderer {
    // MARK: Internal

    /// Map section size in points; rasterised at `mapScale`.
    static let mapSize = CGSize(width: 368, height: 200)
    static let mapScale: CGFloat = 2.0

    /// Render an activation share card to a UIImage (synchronous, no map)
    static func render(
        source: BragSheetSource,
        myGrid: String?,
        metadata: ActivationMetadata? = nil,
        equipment: [ShareCardEquipmentItem] = [],
        statisticianStats: ActivationStatistics? = nil
    ) -> UIImage? {
        let view = ActivationShareCardForExport(
            source: source,
            mapImage: nil,
            metadata: metadata,
            equipment: equipment,
            statisticianStats: statisticianStats
        )
        let height = cardHeight(source: source, statisticianStats: statisticianStats)
        return renderToImage(view, height: height)
    }

    /// Render an activation share card with map snapshot (async)
    static func renderWithMap(
        source: BragSheetSource,
        myGrid: String?,
        metadata: ActivationMetadata? = nil,
        equipment: [ShareCardEquipmentItem] = [],
        statisticianStats: ActivationStatistics? = nil,
        snapshotProvider: ShareMapSnapshotProvider = .mapKit
    ) async -> UIImage? {
        let (resolved, myCoordinate) = await computeMapMarkers(
            source: source, myGrid: myGrid
        )

        let mapImage = await renderMapImage(
            markers: resolved.markers,
            myCoordinate: myCoordinate,
            withoutLocationCount: resolved.withoutLocationCount,
            snapshotProvider: snapshotProvider
        )

        // Render the card with the map image (must be on main thread)
        return await MainActor.run {
            let view = ActivationShareCardForExport(
                source: source,
                mapImage: mapImage,
                metadata: metadata,
                equipment: equipment,
                statisticianStats: statisticianStats,
                withoutLocationCount: resolved.withoutLocationCount
            )
            let height = cardHeight(
                source: source, statisticianStats: statisticianStats
            )
            return renderToImage(view, height: height)
        }
    }

    /// Produce the map section image. Returns `nil` only when there is
    /// nothing at all to place (no contact coordinates and no operator QTH);
    /// a snapshot failure yields the offline fallback instead.
    static func renderMapImage(
        markers: [ShareMapMarker],
        myCoordinate: CLLocationCoordinate2D?,
        withoutLocationCount: Int,
        snapshotProvider: ShareMapSnapshotProvider = .mapKit
    ) async -> UIImage? {
        guard !markers.isEmpty else {
            return nil
        }
        if let image = await generateMapSnapshot(
            markers: markers,
            myCoordinate: myCoordinate,
            snapshotProvider: snapshotProvider
        ) {
            return drawWithoutLocationBadge(count: withoutLocationCount, on: image)
        }
        return ActivationShareOfflineMap.render(
            markers: markers,
            myCoordinate: myCoordinate,
            withoutLocationCount: withoutLocationCount,
            size: mapSize,
            scale: mapScale
        )
    }

    /// Draw the "N contacts without location" caption into an existing
    /// graphics context (bottom-left of the map). No-op when `count` is 0.
    static func drawWithoutLocationBadge(count: Int, in ctx: CGContext, size: CGSize) {
        guard let caption = ActivationShareMapMarkers.caption(forCount: count) else {
            return
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        let text = caption as NSString
        let textSize = text.size(withAttributes: attrs)
        let padding: CGFloat = 5
        let pill = CGRect(
            x: 8,
            y: size.height - textSize.height - padding * 2 - 6,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        ctx.saveGState()
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        ctx.addPath(UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).cgPath)
        ctx.fillPath()
        ctx.restoreGState()
        UIGraphicsPushContext(ctx)
        text.draw(
            at: CGPoint(x: pill.minX + padding, y: pill.minY + padding),
            withAttributes: attrs
        )
        UIGraphicsPopContext()
    }

    static func drawMarker(at point: CGPoint, in context: CGContext, color: UIColor) {
        let headRadius: CGFloat = 4.5
        let pinHeight: CGFloat = 14

        // Pin tip is at `point`; head is above
        let tipY = point.y
        let headCenterY = tipY - pinHeight + headRadius

        // Draw the stem
        context.saveGState()
        context.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: point.x, y: tipY))
        context.addLine(to: CGPoint(x: point.x, y: headCenterY + headRadius))
        context.strokePath()

        // Draw the head circle
        context.setFillColor(color.withAlphaComponent(0.8).cgColor)
        context.fillEllipse(
            in: CGRect(
                x: point.x - headRadius,
                y: headCenterY - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )
        )
        context.restoreGState()
    }

    // MARK: Private

    private static func cardHeight(
        source: BragSheetSource,
        statisticianStats: ActivationStatistics?
    ) -> CGFloat {
        var height: CGFloat = statisticianStats != nil ? 880 : 640
        let hasClubMembers = !ActivationShareCardView.buildClubMembers(
            from: source.qsos
        ).isEmpty
        if hasClubMembers {
            height += 30
        }
        return height
    }

    /// Snapshot the QSO records on the main actor, then resolve coordinates
    /// through the fallback chain off the main thread.
    private static func computeMapMarkers(
        source: BragSheetSource,
        myGrid: String?
    ) async -> (ActivationShareMapMarkers, CLLocationCoordinate2D?) {
        let contacts = source.qsos.map(ActivationShareContact.init(qso:))
        let capturedMyGrid = myGrid

        await Task.yield()

        return await Task.detached {
            let resolved = ActivationShareMapResolver.resolve(
                contacts: contacts, lookups: .live
            )
            let myCoord: CLLocationCoordinate2D? =
                if let grid = capturedMyGrid, grid.count >= 4 {
                    MaidenheadConverter.coordinate(from: grid)
                } else {
                    nil
                }
            return (resolved, myCoord)
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

    /// Tile-backed map (Rust custom styles or MapKit). `nil` when imagery
    /// could not be produced — the caller draws the offline fallback.
    private static func generateMapSnapshot(
        markers: [ShareMapMarker],
        myCoordinate: CLLocationCoordinate2D?,
        snapshotProvider: ShareMapSnapshotProvider
    ) async -> UIImage? {
        let coordinates = markers.map(\.coordinate)
        let mapStyle = ShareMapStyle.current

        let isWide = ActivationMapHelpers.requiresGlobeView(
            qsoCoordinates: coordinates,
            myCoordinate: myCoordinate
        )

        if let image = await ffiMapImage(
            markers: markers, myCoordinate: myCoordinate, mapStyle: mapStyle
        ) {
            return image
        }

        guard
            let region = ActivationMapHelpers.qthCenteredRegion(
                qsoCoordinates: coordinates,
                myCoordinate: myCoordinate
            )
        else {
            return nil
        }

        let useGlobe = mapStyle.shouldUseGlobe(isWideSpan: isWide)

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = mapSize
        options.mapType = useGlobe ? .satellite : .standard
        options.showsBuildings = !useGlobe

        do {
            let snapshot = try await snapshotProvider.snapshot(options)
            return drawAnnotations(
                on: snapshot,
                markers: markers,
                myCoordinate: myCoordinate
            )
        } catch {
            return nil
        }
    }

    /// Rust-rendered map, framed on the operator QTH. Used for the custom
    /// styles (azimuthal + midnight/warm/ocean/arctic/ember), and in Midnight
    /// for MapKit styles whose QTH-centered fit is wider than MapKit can show.
    /// Azimuthal needs a resolved QTH as its projection center; with none,
    /// returns `nil` so the caller falls through to MapKit rather than a
    /// (0,0)-centered map.
    private static func ffiMapImage(
        markers: [ShareMapMarker],
        myCoordinate: CLLocationCoordinate2D?,
        mapStyle: ShareMapStyle
    ) async -> UIImage? {
        let style: ShareMapStyle
        if mapStyle.ffiStyle != nil {
            style = mapStyle
        } else if ActivationMapHelpers.needsWideRenderer(
            qsoCoordinates: markers.map(\.coordinate), myCoordinate: myCoordinate
        ) {
            style = .midnight
        } else {
            return nil
        }
        guard style != .azimuthal || myCoordinate != nil else {
            return nil
        }
        let pins = markers.map { marker in
            ShareMapFFIRenderer.Pin.colored(marker.coordinate, color: marker.rstColor)
        }
        return await ShareMapFFIRenderer.render(
            pins: pins, myCoordinate: myCoordinate,
            style: style,
            size: mapSize, scale: mapScale,
            qthCentered: true
        )
    }

    private static func drawAnnotations(
        on snapshot: ShareMapSnapshot,
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
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(2.5)

            for marker in markers {
                let path = ActivationMapHelpers.geodesicPath(
                    from: myCoord, to: marker.coordinate, segments: 30
                )
                guard path.count >= 2 else {
                    continue
                }

                context.move(to: snapshot.point(path[0]))
                for i in 1 ..< path.count {
                    context.addLine(to: snapshot.point(path[i]))
                }
                context.strokePath()
            }
        }

        // Draw QSO markers with RST-based colors
        for marker in markers {
            let point = snapshot.point(marker.coordinate)
            drawMarker(at: point, in: context, color: marker.rstColor)
        }

        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return finalImage ?? image
    }

    /// Composite the without-location caption onto a finished map image.
    private static func drawWithoutLocationBadge(count: Int, on image: UIImage) -> UIImage {
        guard count > 0 else {
            return image
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            image.draw(at: .zero)
            drawWithoutLocationBadge(count: count, in: context.cgContext, size: image.size)
        }
    }
}
