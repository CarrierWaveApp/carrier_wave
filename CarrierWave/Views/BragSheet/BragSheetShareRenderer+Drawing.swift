// Brag Sheet Share Renderer - Drawing Helpers
//
// Extracted drawing methods for map rendering: grid lines,
// geodesic trace lines, and pin markers.

import MapKit
import UIKit

extension BragSheetShareRenderer {
    // MARK: - Grid Lines (fallback when no map background)

    static func drawGridLines(
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

    // MARK: - Trace Lines

    /// Draw geodesic trace lines from operator location to each cluster.
    static func drawTraceLines(
        ctx: CGContext, size: CGSize, viewport: MapViewport,
        from origin: CLLocationCoordinate2D,
        clusters: [BragSheetMapCluster]
    ) {
        let lineColor = UIColor.white.withAlphaComponent(0.5)
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)

        for cluster in clusters {
            let path = ActivationMapHelpers.geodesicPath(
                from: origin, to: cluster.coordinate, segments: 30
            )
            guard path.count >= 2 else {
                continue
            }

            let firstPt = viewport.project(
                path[0].latitude, path[0].longitude, imageSize: size
            )
            ctx.move(to: firstPt)
            for coord in path.dropFirst() {
                let pt = viewport.project(
                    coord.latitude, coord.longitude, imageSize: size
                )
                ctx.addLine(to: pt)
            }
            ctx.strokePath()
        }
    }

    // MARK: - Pin Drawing

    /// Draw a traditional map pin at the given point.
    /// Pin size is fixed/small; color varies by count.
    static func drawPinMarker(
        at point: CGPoint, in ctx: CGContext, count: Int
    ) {
        let color = pinColor(for: count)
        let pinHeight: CGFloat = 14
        let headRadius: CGFloat = 4.5

        // Pin tip is at `point`; head is above
        let tipY = point.y
        let headCenterY = tipY - pinHeight + headRadius

        // Draw the needle (line from tip to bottom of head)
        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: point.x, y: tipY))
        ctx.addLine(to: CGPoint(x: point.x, y: headCenterY + headRadius))
        ctx.strokePath()

        // Draw the head circle
        ctx.setFillColor(color.withAlphaComponent(0.8).cgColor)
        ctx.fillEllipse(
            in: CGRect(
                x: point.x - headRadius,
                y: headCenterY - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )
        )
        ctx.restoreGState()
    }

    static func pinColor(for count: Int) -> UIColor {
        switch count {
        case 1 ... 5: UIColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1)
        case 6 ... 20: UIColor(red: 0.90, green: 0.85, blue: 0.45, alpha: 1)
        case 21 ... 50: UIColor(red: 0.90, green: 0.65, blue: 0.35, alpha: 1)
        default: UIColor(red: 0.90, green: 0.45, blue: 0.40, alpha: 1)
        }
    }
}
