// Canvas-based path map for TOTA brag sheets.
//
// Replaces the live `Map(...)` for the path/tile section so the brag sheet
// snapshots correctly via ImageRenderer (MapKit live views don't render in
// SwiftUI snapshots). Draws:
//   - Tile boundary polygon(s) (purple outline + light fill)
//   - Track polyline (cyan)
//   - Start (green) + end (red) dots when track has > 1 point
//
// Projection is equirectangular against the bounds enclosing the track and
// any visible tile corners — accurate enough at activation scale.

import CoreLocation
import MapKit
import SwiftUI

struct TOTAPathCanvas: View {
    // MARK: Internal

    let trackCoords: [CLLocationCoordinate2D]
    /// Each tile's southwest + northeast corners.
    let tileBounds: [(sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D)]
    /// Used when no track is present — center the view on this region.
    let fallbackRegion: MKCoordinateRegion

    var body: some View {
        Canvas { ctx, size in
            let bounds = computeBounds(size: size)
            // Background — slightly lighter purple than the card so the map
            // sub-section reads as its own surface on the brag sheet.
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.white.opacity(0.06))
            )
            drawTiles(in: ctx, size: size, bounds: bounds)
            drawTrack(in: ctx, size: size, bounds: bounds)
        }
    }

    // MARK: Private

    private struct ProjectionBounds {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double
    }

    private func computeBounds(size: CGSize) -> ProjectionBounds {
        var lats: [Double] = trackCoords.map(\.latitude)
        var lons: [Double] = trackCoords.map(\.longitude)
        for bounds in tileBounds {
            lats.append(contentsOf: [bounds.sw.latitude, bounds.ne.latitude])
            lons.append(contentsOf: [bounds.sw.longitude, bounds.ne.longitude])
        }
        if lats.isEmpty {
            let region = fallbackRegion
            let halfLat = region.span.latitudeDelta / 2
            let halfLon = region.span.longitudeDelta / 2
            return ProjectionBounds(
                minLat: region.center.latitude - halfLat,
                maxLat: region.center.latitude + halfLat,
                minLon: region.center.longitude - halfLon,
                maxLon: region.center.longitude + halfLon
            )
        }
        let pad = 0.10
        let minLat = (lats.min() ?? 0)
        let maxLat = (lats.max() ?? 0)
        let minLon = (lons.min() ?? 0)
        let maxLon = (lons.max() ?? 0)
        let latPad = max((maxLat - minLat) * pad, 0.001)
        let lonPad = max((maxLon - minLon) * pad, 0.001)
        return ProjectionBounds(
            minLat: minLat - latPad,
            maxLat: maxLat + latPad,
            minLon: minLon - lonPad,
            maxLon: maxLon + lonPad
        )
    }

    private func project(
        _ coord: CLLocationCoordinate2D, in size: CGSize, bounds: ProjectionBounds
    ) -> CGPoint {
        let lonRange = max(bounds.maxLon - bounds.minLon, 0.0001)
        let latRange = max(bounds.maxLat - bounds.minLat, 0.0001)
        let xFrac = (coord.longitude - bounds.minLon) / lonRange
        let yFrac = (bounds.maxLat - coord.latitude) / latRange
        return CGPoint(x: xFrac * size.width, y: yFrac * size.height)
    }

    private func drawTiles(
        in ctx: GraphicsContext, size: CGSize, bounds: ProjectionBounds
    ) {
        for tile in tileBounds {
            let nw = CLLocationCoordinate2D(latitude: tile.ne.latitude, longitude: tile.sw.longitude)
            let ne = tile.ne
            let se = CLLocationCoordinate2D(latitude: tile.sw.latitude, longitude: tile.ne.longitude)
            let sw = tile.sw
            var path = Path()
            path.move(to: project(nw, in: size, bounds: bounds))
            path.addLine(to: project(ne, in: size, bounds: bounds))
            path.addLine(to: project(se, in: size, bounds: bounds))
            path.addLine(to: project(sw, in: size, bounds: bounds))
            path.closeSubpath()
            // Outline only — no fill. A filled tile that fills most of the
            // canvas reads as a solid color block rather than a boundary.
            ctx.stroke(
                path,
                with: .color(Color.purple.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
            )
        }
    }

    private func drawTrack(
        in ctx: GraphicsContext, size: CGSize, bounds: ProjectionBounds
    ) {
        guard trackCoords.count > 1 else {
            return
        }
        var path = Path()
        for (i, coord) in trackCoords.enumerated() {
            let pt = project(coord, in: size, bounds: bounds)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        ctx.stroke(path, with: .color(.cyan), lineWidth: 2.5)
        if let first = trackCoords.first {
            let pt = project(first, in: size, bounds: bounds)
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                with: .color(.green)
            )
        }
        if let last = trackCoords.last {
            let pt = project(last, in: size, bounds: bounds)
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                with: .color(.red)
            )
        }
    }
}
