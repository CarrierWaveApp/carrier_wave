// Brag Sheet Share Renderer
//
// Renders BragSheetShareCardView to UIImage with a map.
// Clusters QSOs by grid square with size proportional to count.
// Uses equirectangular projection for cluster positioning (guarantees all
// clusters are visible) with an MKMapSnapshotter background for context.
//
// Known issue: Map rendering is not correct for wide geographic spans (e.g. US+EU+Japan).
// MKMapSnapshotter background doesn't align well with equirectangular cluster
// overlay at world scale. Needs a better approach for global QSO coverage.

import MapKit
import SwiftUI
import UIKit

// MARK: - BragSheetMapCluster

/// A cluster of QSOs in the same grid square.
private struct BragSheetMapCluster {
    let coordinate: CLLocationCoordinate2D
    let count: Int
}

// MARK: - BragSheetShareRenderer

@MainActor
enum BragSheetShareRenderer {
    // MARK: Internal

    /// Input for rendering a brag sheet share card.
    struct Input {
        let result: BragSheetComputedResult
        let config: BragSheetPeriodConfig
        let period: BragSheetPeriod
        let callsign: String
        let statisticianStats: BragSheetStatisticianData?
        let snapshots: [BragSheetQSOSnapshot]
    }

    /// Render a brag sheet share card with map to UIImage (async).
    static func renderWithMap(input: Input) async -> UIImage? {
        let clusters = await computeClusters(from: input.snapshots)

        let mapImage: UIImage? =
            if !clusters.isEmpty {
                await drawMap(clusters: clusters)
            } else {
                nil
            }

        let view = BragSheetShareCardView(
            result: input.result,
            config: input.config,
            period: input.period,
            callsign: input.callsign,
            mapImage: mapImage,
            statisticianStats: input.statisticianStats
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        renderer.isOpaque = true
        return renderer.uiImage
    }

    // MARK: Private

    // MARK: - Viewport

    private struct MapViewport {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double

        var centerLat: Double {
            (minLat + maxLat) / 2
        }

        var centerLon: Double {
            (minLon + maxLon) / 2
        }

        var latSpan: Double {
            maxLat - minLat
        }

        var lonSpan: Double {
            maxLon - minLon
        }

        func project(
            _ lat: Double, _ lon: Double, imageSize: CGSize
        ) -> CGPoint {
            let x = (lon - minLon) / (maxLon - minLon)
                * Double(imageSize.width)
            let y = (1 - (lat - minLat) / (maxLat - minLat))
                * Double(imageSize.height)
            return CGPoint(x: x, y: y)
        }
    }

    private static let mapWidth: CGFloat = 368
    private static let mapHeight: CGFloat = 200
    private static let mapScale: CGFloat = 2.0

    private static func computeClusters(
        from snapshots: [BragSheetQSOSnapshot]
    ) async -> [BragSheetMapCluster] {
        // Decide clustering granularity based on geographic spread.
        // Use 2-char (field, ~20x10) for wide views, 4-char for focused.
        let lons = snapshots.compactMap(\.theirGrid).compactMap { grid -> Double? in
            guard grid.count >= 4 else {
                return nil
            }
            return MaidenheadConverter.coordinate(
                from: String(grid.prefix(4))
            )?.longitude
        }
        let lonSpread = (lons.max() ?? 0) - (lons.min() ?? 0)
        let prefixLength = lonSpread > 50 ? 2 : 4

        var gridCounts: [String: Int] = [:]
        for snap in snapshots {
            guard let grid = snap.theirGrid,
                  grid.count >= prefixLength
            else {
                continue
            }
            let prefix = String(grid.prefix(prefixLength)).uppercased()
            gridCounts[prefix, default: 0] += 1
        }
        let gridData = gridCounts

        await Task.yield()

        return await Task.detached {
            gridData.compactMap { grid, count in
                // Pad 2-char field grids to 4-char for coordinate lookup
                let lookupGrid = grid.count < 4 ? grid + "55" : grid
                guard let coord = MaidenheadConverter.coordinate(
                    from: lookupGrid
                ) else {
                    return nil
                }
                return BragSheetMapCluster(coordinate: coord, count: count)
            }
        }.value
    }

    // MARK: - Map Drawing

    /// Draw a map with MKMapSnapshotter background and equirectangular
    /// cluster overlay. The background provides earth imagery context;
    /// cluster positions use our own projection for guaranteed visibility.
    private static func drawMap(
        clusters: [BragSheetMapCluster]
    ) async -> UIImage {
        let viewport = computeViewport(clusters: clusters)

        // Try to get a map background from MKMapSnapshotter
        let background = await renderBackground(viewport: viewport)

        let size = CGSize(width: mapWidth, height: mapHeight)

        UIGraphicsBeginImageContextWithOptions(size, true, mapScale)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return UIImage()
        }

        // Draw background (map snapshot or dark fallback)
        if let bg = background {
            bg.draw(in: CGRect(origin: .zero, size: size))
        } else {
            ctx.setFillColor(
                UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1).cgColor
            )
            ctx.fill(CGRect(origin: .zero, size: size))
            drawGridLines(ctx: ctx, size: size, viewport: viewport)
        }

        // Draw clusters using equirectangular projection
        let maxCount = clusters.map(\.count).max() ?? 1
        for cluster in clusters {
            let pt = viewport.project(
                cluster.coordinate.latitude,
                cluster.coordinate.longitude,
                imageSize: size
            )
            let fraction = Double(cluster.count)
                / Double(max(maxCount, 1))
            let markerSize = CGFloat(10 + fraction * 30)
            drawClusterMarker(
                at: pt, in: ctx, size: markerSize, count: cluster.count
            )
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }

    private static func computeViewport(
        clusters: [BragSheetMapCluster]
    ) -> MapViewport {
        let lats = clusters.map(\.coordinate.latitude)
        let lons = clusters.map(\.coordinate.longitude)

        guard let rawMinLat = lats.min(), let rawMaxLat = lats.max(),
              let rawMinLon = lons.min(), let rawMaxLon = lons.max()
        else {
            return MapViewport(
                minLat: -60, maxLat: 60, minLon: -180, maxLon: 180
            )
        }

        let latPad = max((rawMaxLat - rawMinLat) * 0.2, 5)
        let lonPad = max((rawMaxLon - rawMinLon) * 0.15, 5)

        var vMinLat = rawMinLat - latPad
        var vMaxLat = rawMaxLat + latPad
        var vMinLon = rawMinLon - lonPad
        var vMaxLon = rawMaxLon + lonPad

        // Match image aspect ratio (368:200 = 1.84:1)
        let imageAspect = Double(mapWidth / mapHeight)
        let latRange = vMaxLat - vMinLat
        let lonRange = vMaxLon - vMinLon

        if lonRange / latRange > imageAspect {
            let newLatRange = lonRange / imageAspect
            let center = (vMinLat + vMaxLat) / 2
            vMinLat = center - newLatRange / 2
            vMaxLat = center + newLatRange / 2
        } else {
            let newLonRange = latRange * imageAspect
            let center = (vMinLon + vMaxLon) / 2
            vMinLon = center - newLonRange / 2
            vMaxLon = center + newLonRange / 2
        }

        return MapViewport(
            minLat: max(vMinLat, -85), maxLat: min(vMaxLat, 85),
            minLon: max(vMinLon, -180), maxLon: min(vMaxLon, 180)
        )
    }

    // MARK: - Map Background

    /// Render an MKMapSnapshotter background matching the viewport.
    /// Returns nil if the snapshotter fails.
    private static func renderBackground(
        viewport: MapViewport
    ) async -> UIImage? {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: viewport.centerLat,
                longitude: viewport.centerLon
            ),
            span: MKCoordinateSpan(
                latitudeDelta: viewport.latSpan,
                longitudeDelta: viewport.lonSpan
            )
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: mapWidth, height: mapHeight)
        options.mapType = .standard
        options.showsBuildings = false

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()
            return snapshot.image
        } catch {
            return nil
        }
    }

    // MARK: - Grid Lines (fallback when no map background)

    private static func drawGridLines(
        ctx: CGContext, size: CGSize, viewport: MapViewport
    ) {
        let lonRange = viewport.lonSpan
        let latRange = viewport.latSpan

        let lonStep: Double =
            if lonRange > 200 {
                60
            } else if lonRange > 100 {
                30
            } else if lonRange > 40 {
                15
            } else {
                10
            }

        let latStep: Double =
            if latRange > 100 {
                30
            } else if latRange > 50 {
                15
            } else {
                10
            }

        ctx.setStrokeColor(
            UIColor.white.withAlphaComponent(0.08).cgColor
        )
        ctx.setLineWidth(0.5)

        let firstLon = (viewport.minLon / lonStep).rounded(.up) * lonStep
        var lon = firstLon
        while lon <= viewport.maxLon {
            let p1 = viewport.project(viewport.minLat, lon, imageSize: size)
            let p2 = viewport.project(viewport.maxLat, lon, imageSize: size)
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.strokePath()
            lon += lonStep
        }

        let firstLat = (viewport.minLat / latStep).rounded(.up) * latStep
        var lat = firstLat
        while lat <= viewport.maxLat {
            let p1 = viewport.project(lat, viewport.minLon, imageSize: size)
            let p2 = viewport.project(lat, viewport.maxLon, imageSize: size)
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.strokePath()
            lat += latStep
        }
    }

    // MARK: - Cluster Drawing

    private static func drawClusterMarker(
        at point: CGPoint, in context: CGContext,
        size: CGFloat, count: Int
    ) {
        let color = clusterColor(for: count)

        // Glow effect
        context.saveGState()
        context.setShadow(
            offset: .zero, blur: size * 0.6,
            color: color.withAlphaComponent(0.4).cgColor
        )
        context.setFillColor(color.withAlphaComponent(0.5).cgColor)
        context.fillEllipse(
            in: CGRect(
                x: point.x - size / 2, y: point.y - size / 2,
                width: size, height: size
            )
        )
        context.restoreGState()

        // Solid border
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(
            in: CGRect(
                x: point.x - size / 2, y: point.y - size / 2,
                width: size, height: size
            )
        )

        // Count label for clusters with 2+ QSOs
        if count >= 2, size >= 16 {
            let text = "\(count)" as NSString
            let fontSize: CGFloat = min(size * 0.4, 14)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: point.x - textSize.width / 2,
                y: point.y - textSize.height / 2,
                width: textSize.width, height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)
        }
    }

    private static func clusterColor(for count: Int) -> UIColor {
        switch count {
        case 1 ... 5: UIColor.systemGreen
        case 6 ... 20: UIColor.systemYellow
        case 21 ... 50: UIColor.systemOrange
        default: UIColor.systemRed
        }
    }
}
