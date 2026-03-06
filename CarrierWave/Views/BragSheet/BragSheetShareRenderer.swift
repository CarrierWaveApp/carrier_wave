// Brag Sheet Share Renderer
//
// Renders BragSheetShareCardView to UIImage with a map.
// Clusters QSOs by grid square with size proportional to count.
// Uses equirectangular projection for cluster positioning (guarantees all
// clusters are visible) with an MKMapSnapshotter background for context.
//
// For wide geographic spans (>90° longitude), uses azimuthal equidistant
// projection centered on the operator's QTH via AzimuthalMapRenderer.

import CarrierWaveData
import MapKit
import SwiftUI
import UIKit

// MARK: - BragSheetMapCluster

/// A cluster of QSOs in the same grid square.
struct BragSheetMapCluster {
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

        /// Most common operator grid (for drawing trace lines).
        var myGrid: String? {
            var counts: [String: Int] = [:]
            for snap in snapshots {
                guard let grid = snap.myGrid, grid.count >= 4 else {
                    continue
                }
                counts[String(grid.prefix(4)).uppercased(), default: 0] += 1
            }
            return counts.max(by: { $0.value < $1.value })?.key
        }
    }

    // MARK: - Viewport

    struct MapViewport {
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

    /// Render a brag sheet share card with map to UIImage (async).
    static func renderWithMap(input: Input) async -> UIImage? {
        let clusters = await computeClusters(from: input.snapshots)
        let myCoordinate = input.myGrid.flatMap {
            MaidenheadConverter.coordinate(from: $0)
        }

        let mapImage: UIImage? =
            if !clusters.isEmpty {
                await drawMap(clusters: clusters, myCoordinate: myCoordinate)
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
    ///
    /// For wide geographic spans (>90° longitude), switches to an
    /// azimuthal equidistant projection centered on the operator's QTH.
    private static func drawMap(
        clusters: [BragSheetMapCluster],
        myCoordinate: CLLocationCoordinate2D? = nil
    ) async -> UIImage {
        // Use azimuthal projection for wide spans when we have a center point
        if let myCoord = myCoordinate, isWideSpan(clusters: clusters, myCoordinate: myCoord) {
            let size = CGSize(width: mapWidth, height: mapHeight)
            return AzimuthalMapRenderer.render(
                clusters: clusters, myCoordinate: myCoord,
                size: size, scale: mapScale
            )
        }

        let viewport = computeViewport(
            clusters: clusters, myCoordinate: myCoordinate
        )

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

        // Draw geodesic trace lines from operator to each cluster
        if let myCoord = myCoordinate {
            drawTraceLines(
                ctx: ctx, size: size, viewport: viewport,
                from: myCoord, clusters: clusters
            )
        }

        // Draw pin markers using equirectangular projection
        for cluster in clusters {
            let pt = viewport.project(
                cluster.coordinate.latitude,
                cluster.coordinate.longitude,
                imageSize: size
            )
            drawPinMarker(at: pt, in: ctx, count: cluster.count)
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }

    /// Check if the cluster + operator span exceeds 90° longitude,
    /// which makes the equirectangular projection illegible.
    private static func isWideSpan(
        clusters: [BragSheetMapCluster],
        myCoordinate: CLLocationCoordinate2D
    ) -> Bool {
        var lons = clusters.map(\.coordinate.longitude)
        lons.append(myCoordinate.longitude)
        guard let minLon = lons.min(), let maxLon = lons.max() else {
            return false
        }
        let directSpan = maxLon - minLon
        let datelineSpan = 360 - directSpan
        return min(directSpan, datelineSpan) > 90
    }

    private static func computeViewport(
        clusters: [BragSheetMapCluster],
        myCoordinate: CLLocationCoordinate2D? = nil
    ) -> MapViewport {
        var lats = clusters.map(\.coordinate.latitude)
        var lons = clusters.map(\.coordinate.longitude)
        if let myCoord = myCoordinate {
            lats.append(myCoord.latitude)
            lons.append(myCoord.longitude)
        }

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
}
