// Brag Sheet Share Renderer
//
// Renders BragSheetShareCardView to UIImage with a map.
// Clusters QSOs by grid square with size proportional to count.
// Map projection controlled by ShareMapStyle user preference:
// adaptive (2D/3D), flat, globe, or azimuthal.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
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
        let config: FfiBragPeriodConfig
        let period: FfiBragPeriod
        let callsign: String
        let catalog: [FfiBragStatType: FfiBragStatMeta]
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

    /// Framed region for projecting lat/lon to screen coordinates.
    ///
    /// `minLon` / `maxLon` may fall outside `[-180, 180]` when the viewport
    /// wraps the antimeridian — e.g. `(170, 370)` for a US operator with
    /// contacts in New Zealand and Europe. See
    /// `ActivationMapHelpers.tightestLongitudeBounds` for how this is
    /// computed. `normalizedCenterLon` brings the center back into
    /// `[-180, 180]` for `MKCoordinateRegion`.
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

        /// Center longitude wrapped into `[-180, 180]` for MapKit APIs.
        var normalizedCenterLon: Double {
            let raw = centerLon
            let shifted = (raw + 180).truncatingRemainder(dividingBy: 360)
            let positive = shifted < 0 ? shifted + 360 : shifted
            return positive - 180
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
            // Pick the representation of `lon` closest to the viewport
            // center. For normal viewports this is a no-op; for wrapping
            // viewports (e.g. minLon=170, maxLon=370) this pulls -120
            // into 240 so the cluster projects correctly. The key
            // property: points in the visible arc land in `[0, 1]` and
            // off-viewport points land just past the nearest edge — not
            // flipped to the opposite side, which would create the
            // zigzag polygon fill bug seen on Aleutians-type coastlines.
            let centerLon = (minLon + maxLon) / 2
            var projectedLon = lon
            let diff = projectedLon - centerLon
            if diff > 180 {
                projectedLon -= 360
            } else if diff < -180 {
                projectedLon += 360
            }
            let xFrac = (projectedLon - minLon) / (maxLon - minLon)
            let yFrac = 1 - (lat - minLat) / (maxLat - minLat)
            return CGPoint(
                x: xFrac * Double(imageSize.width),
                y: yFrac * Double(imageSize.height)
            )
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
            catalog: input.catalog,
            mapImage: mapImage,
            statisticianStats: input.statisticianStats
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Padded, aspect-fit (368:200) viewport enclosing `coordinates`. Shared
    /// with the activation share card's offline fallback map so both cards
    /// frame the same way when no tile background is available.
    static func computeViewport(
        coordinates: [CLLocationCoordinate2D]
    ) -> MapViewport {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)

        guard let rawMinLat = lats.min(), let rawMaxLat = lats.max(),
              let lonBounds = ActivationMapHelpers.tightestLongitudeBounds(lons)
        else {
            return MapViewport(
                minLat: -60, maxLat: 60, minLon: -180, maxLon: 180
            )
        }

        let rawMinLon = lonBounds.minLon
        let rawMaxLon = lonBounds.maxLon

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

        // If the aspect fit expanded lon past a full globe, clamp to 360°.
        if vMaxLon - vMinLon > 360 {
            let centerLon = (vMinLon + vMaxLon) / 2
            vMinLon = centerLon - 180
            vMaxLon = centerLon + 180
        }

        // Note: lat is clamped to avoid near-pole issues, but lon is left
        // unbounded so antimeridian-spanning viewports keep their shifted
        // representation (e.g. minLon=170, maxLon=370).
        return MapViewport(
            minLat: max(vMinLat, -85), maxLat: min(vMaxLat, 85),
            minLon: vMinLon, maxLon: vMaxLon
        )
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

    /// Draw a map respecting the user's ShareMapStyle preference.
    private static func drawMap(
        clusters: [BragSheetMapCluster],
        myCoordinate: CLLocationCoordinate2D? = nil
    ) async -> UIImage {
        let mapStyle = ShareMapStyle.current
        let size = CGSize(width: mapWidth, height: mapHeight)

        // Custom styles (azimuthal + midnight/warm/ocean/arctic/ember)
        // render via the Rust `renderShareMap` FFI. Count-ramp pins.
        //
        // Azimuthal requires a resolved operator QTH (it is the projection
        // center) — with no QTH the old code fell through to MapKit rather than
        // render a meaningless (0,0)-centered polar map, so gate it here.
        if mapStyle.ffiStyle != nil,
           mapStyle != .azimuthal || myCoordinate != nil
        {
            let pins = clusters.map { cluster in
                ShareMapFFIRenderer.Pin.counted(
                    cluster.coordinate, count: cluster.count
                )
            }
            if let image = await ShareMapFFIRenderer.render(
                pins: pins, myCoordinate: myCoordinate,
                style: mapStyle, size: size, scale: mapScale
            ) {
                return image
            }
        }

        let useGlobe = mapStyle.shouldUseGlobe(
            isWideSpan: myCoordinate.map {
                isWideSpan(clusters: clusters, myCoordinate: $0)
            } ?? false
        )

        let viewport = computeViewport(
            clusters: clusters, myCoordinate: myCoordinate
        )

        let background = await renderBackground(
            viewport: viewport, useGlobe: useGlobe
        )

        return renderComposite(
            size: size, viewport: viewport, background: background,
            clusters: clusters, myCoordinate: myCoordinate
        )
    }

    private static func renderComposite(
        size: CGSize, viewport: MapViewport, background: UIImage?,
        clusters: [BragSheetMapCluster],
        myCoordinate: CLLocationCoordinate2D?
    ) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, true, mapScale)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return UIImage()
        }

        if let bg = background {
            bg.draw(in: CGRect(origin: .zero, size: size))
            // Overlay the day/night terminator only on the real-tile
            // background. Custom flat themes have their own designed look.
            drawTerminator(
                size: size, viewport: viewport, date: Date()
            )
        } else {
            ctx.setFillColor(
                UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1).cgColor
            )
            ctx.fill(CGRect(origin: .zero, size: size))
            drawGridLines(ctx: ctx, size: size, viewport: viewport)
        }

        if let myCoord = myCoordinate {
            drawTraceLines(
                ctx: ctx, size: size, viewport: viewport,
                from: myCoord, clusters: clusters
            )
        }

        for cluster in clusters {
            let pt = viewport.project(
                cluster.coordinate.latitude,
                cluster.coordinate.longitude,
                imageSize: size
            )
            drawDotMarker(at: pt, in: ctx, count: cluster.count)
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }

    /// Check if the cluster + operator span exceeds 90° longitude.
    private static func isWideSpan(
        clusters: [BragSheetMapCluster],
        myCoordinate: CLLocationCoordinate2D
    ) -> Bool {
        var lons = clusters.map(\.coordinate.longitude)
        lons.append(myCoordinate.longitude)
        guard let bounds = ActivationMapHelpers.tightestLongitudeBounds(lons) else {
            return false
        }
        return (bounds.maxLon - bounds.minLon) > 90
    }

    private static func computeViewport(
        clusters: [BragSheetMapCluster],
        myCoordinate: CLLocationCoordinate2D? = nil
    ) -> MapViewport {
        var coordinates = clusters.map(\.coordinate)
        if let myCoord = myCoordinate {
            coordinates.append(myCoord)
        }
        return computeViewport(coordinates: coordinates)
    }

    // MARK: - Map Background

    /// Render an MKMapSnapshotter background matching the viewport.
    /// Returns nil if the snapshotter fails.
    private static func renderBackground(
        viewport: MapViewport, useGlobe: Bool = false
    ) async -> UIImage? {
        // The viewport may span the antimeridian (e.g. minLon=170, maxLon=370).
        // MKCoordinateRegion expects a center in [-180, 180] and MKCoordinateSpan
        // rejects a 360° longitude span, so normalize before handing off.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: viewport.centerLat,
                longitude: viewport.normalizedCenterLon
            ),
            span: MKCoordinateSpan(
                latitudeDelta: viewport.latSpan,
                longitudeDelta: min(viewport.lonSpan, 359.9)
            )
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: mapWidth, height: mapHeight)
        options.mapType = useGlobe ? .satellite : .standard
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
