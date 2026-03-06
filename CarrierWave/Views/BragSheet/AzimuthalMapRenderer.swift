// Azimuthal Map Renderer
//
// CoreGraphics renderer that draws an azimuthal equidistant projection map
// centered on the operator's QTH. Used by BragSheetShareRenderer and
// ActivationShareRenderer when geographic span is too wide for flat maps.
//
// The projection preserves distances and bearings from center — ideal for
// showing QSOs across the globe on a ham radio share card.

import CarrierWaveCore
import MapKit
import UIKit

// MARK: - AzimuthalMapRenderer

@MainActor
enum AzimuthalMapRenderer {
    // MARK: Internal

    /// Render for brag sheet clusters (count-based pin colors).
    static func render(
        clusters: [BragSheetMapCluster],
        myCoordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat
    ) -> UIImage {
        let coordinates = clusters.map(\.coordinate)
        return renderBase(
            myCoordinate: myCoordinate, coordinates: coordinates,
            size: size, scale: scale
        ) { ctx, mapCtx in
            for cluster in clusters {
                guard let pt = mapCtx.screenPoint(
                    latDeg: cluster.coordinate.latitude,
                    lonDeg: cluster.coordinate.longitude
                ) else {
                    continue
                }
                BragSheetShareRenderer.drawPinMarker(
                    at: pt, in: ctx, count: cluster.count
                )
            }
        }
    }

    /// Render for activation share markers (RST-colored pins).
    static func render(
        markers: [ShareMapMarker],
        myCoordinate: CLLocationCoordinate2D,
        size: CGSize,
        scale: CGFloat
    ) -> UIImage {
        let coordinates = markers.map(\.coordinate)
        return renderBase(
            myCoordinate: myCoordinate, coordinates: coordinates,
            size: size, scale: scale
        ) { ctx, mapCtx in
            for marker in markers {
                guard let pt = mapCtx.screenPoint(
                    latDeg: marker.coordinate.latitude,
                    lonDeg: marker.coordinate.longitude
                ) else {
                    continue
                }
                drawPinMarker(at: pt, in: ctx, color: marker.rstColor)
            }
        }
    }

    // MARK: Private

    /// Bundles projection, screen center, and radius for drawing helpers.
    private struct MapContext {
        let proj: AzimuthalProjection
        let center: CGPoint
        let radius: CGFloat

        func screenPoint(latDeg: Double, lonDeg: Double) -> CGPoint? {
            guard let projected = proj.project(latDeg: latDeg, lonDeg: lonDeg) else {
                return nil
            }
            let x = center.x + CGFloat(projected.x) * radius
            // Flip y: projection has y-up, screen has y-down
            let y = center.y - CGFloat(projected.y) * radius
            return CGPoint(x: x, y: y)
        }
    }

    private static let bgColor = UIColor(
        red: 0.059, green: 0.059, blue: 0.118, alpha: 1
    ) // #0F0F1E
    private static let oceanColor = UIColor(
        red: 0.07, green: 0.08, blue: 0.16, alpha: 1
    )
    private static let mapPadding: CGFloat = 8

    /// Common base rendering: background, coastlines, range rings, trace
    /// lines, center marker. The `drawMarkers` closure draws type-specific pins.
    private static func renderBase(
        myCoordinate: CLLocationCoordinate2D,
        coordinates: [CLLocationCoordinate2D],
        size: CGSize, scale: CGFloat,
        drawMarkers: (CGContext, MapContext) -> Void
    ) -> UIImage {
        let proj = AzimuthalProjection(
            centerLatDeg: myCoordinate.latitude,
            centerLonDeg: myCoordinate.longitude
        )

        UIGraphicsBeginImageContextWithOptions(size, true, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return UIImage()
        }

        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        let mapRadius = min(size.width, size.height) / 2 - mapPadding
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        ctx.saveGState()
        ctx.setFillColor(oceanColor.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: center.x - mapRadius, y: center.y - mapRadius,
            width: mapRadius * 2, height: mapRadius * 2
        ))
        ctx.restoreGState()

        let mapCtx = MapContext(
            proj: proj, center: center, radius: mapRadius
        )

        drawCoastlines(ctx: ctx, map: mapCtx)
        drawRangeRings(ctx: ctx, center: center, radius: mapRadius)
        drawTraceLines(
            ctx: ctx, map: mapCtx,
            myCoord: myCoordinate, coordinates: coordinates
        )

        drawMarkers(ctx, mapCtx)
        drawCenterMarker(ctx: ctx, center: center)

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }

    // MARK: - Coastlines

    private static func drawCoastlines(
        ctx: CGContext, map: MapContext
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(
            UIColor.white.withAlphaComponent(0.15).cgColor
        )
        ctx.setLineWidth(0.5)
        ctx.setLineJoin(.round)

        for continent in CoastlineData.continents {
            guard continent.count >= 3 else {
                continue
            }

            var started = false
            for point in continent {
                guard let sp = map.screenPoint(
                    latDeg: point.lat, lonDeg: point.lon
                ) else {
                    // Point off the projection — break the path
                    if started {
                        ctx.strokePath()
                        started = false
                    }
                    continue
                }

                if !started {
                    ctx.move(to: sp)
                    started = true
                } else {
                    ctx.addLine(to: sp)
                }
            }

            // Close the polygon back to first point
            if started, let first = continent.first,
               let sp = map.screenPoint(
                   latDeg: first.lat, lonDeg: first.lon
               )
            {
                ctx.addLine(to: sp)
            }
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    // MARK: - Range Rings

    private static func drawRangeRings(
        ctx: CGContext, center: CGPoint, radius: CGFloat
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(
            UIColor.white.withAlphaComponent(0.08).cgColor
        )
        ctx.setLineWidth(0.5)

        // Earth circumference ~40,075 km, half = ~20,037 km
        // radius maps to π radians = 20,037 km
        // Ring every 5,000 km = 5000/20037 * radius ≈ 0.2495 * radius
        let ringDistanceKm: Double = 5_000
        let earthHalfCircumKm: Double = 20_037
        let ringFraction = CGFloat(ringDistanceKm / earthHalfCircumKm)

        let dashLengths: [CGFloat] = [4, 4]
        ctx.setLineDash(phase: 0, lengths: dashLengths)

        var ringRadius = ringFraction * radius
        var distanceKm = ringDistanceKm
        while ringRadius < radius {
            ctx.strokeEllipse(in: CGRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            ))

            // Label the ring
            drawRingLabel(
                ctx: ctx, center: center, ringRadius: ringRadius,
                distanceKm: distanceKm
            )

            ringRadius += ringFraction * radius
            distanceKm += ringDistanceKm
        }

        // Reset dash
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.restoreGState()
    }

    private static func drawRingLabel(
        ctx: CGContext, center: CGPoint,
        ringRadius: CGFloat, distanceKm: Double
    ) {
        let text: String
        let distanceMi = distanceKm * 0.621371
        if distanceMi >= 1_000 {
            text = String(format: "%.0fk mi", distanceMi / 1_000)
        } else {
            text = String(format: "%.0f mi", distanceMi)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.2),
        ]

        let nsText = text as NSString
        let textSize = nsText.size(withAttributes: attrs)

        // Position label at top of ring
        let labelPoint = CGPoint(
            x: center.x - textSize.width / 2,
            y: center.y - ringRadius - textSize.height - 1
        )

        // Only draw if within image bounds (rough check)
        guard labelPoint.y > 0 else {
            return
        }

        nsText.draw(at: labelPoint, withAttributes: attrs)
    }

    // MARK: - Trace Lines

    private static func drawTraceLines(
        ctx: CGContext, map: MapContext,
        myCoord: CLLocationCoordinate2D,
        coordinates: [CLLocationCoordinate2D]
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(
            UIColor.white.withAlphaComponent(0.5).cgColor
        )
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)

        for coord in coordinates {
            let path = AzimuthalProjection.greatCirclePath(
                fromLat: myCoord.latitude,
                fromLon: myCoord.longitude,
                toLat: coord.latitude,
                toLon: coord.longitude,
                segments: 40
            )
            guard path.count >= 2 else {
                continue
            }

            var started = false
            for point in path {
                guard let sp = map.screenPoint(
                    latDeg: point.lat, lonDeg: point.lon
                ) else {
                    if started {
                        ctx.strokePath()
                        started = false
                    }
                    continue
                }

                if !started {
                    ctx.move(to: sp)
                    started = true
                } else {
                    ctx.addLine(to: sp)
                }
            }
            if started {
                ctx.strokePath()
            }
        }

        ctx.restoreGState()
    }

    // MARK: - Pin Marker (RST-colored)

    private static func drawPinMarker(
        at point: CGPoint, in ctx: CGContext, color: UIColor
    ) {
        let headRadius: CGFloat = 4.5
        let pinHeight: CGFloat = 14
        let tipY = point.y
        let headCenterY = tipY - pinHeight + headRadius

        ctx.saveGState()
        ctx.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: point.x, y: tipY))
        ctx.addLine(to: CGPoint(x: point.x, y: headCenterY + headRadius))
        ctx.strokePath()

        ctx.setFillColor(color.withAlphaComponent(0.8).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: point.x - headRadius, y: headCenterY - headRadius,
            width: headRadius * 2, height: headRadius * 2
        ))
        ctx.restoreGState()
    }

    // MARK: - Center Marker

    private static func drawCenterMarker(
        ctx: CGContext, center: CGPoint
    ) {
        let dotRadius: CGFloat = 5
        ctx.saveGState()

        // Outer glow
        ctx.setFillColor(
            UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.3).cgColor
        )
        ctx.fillEllipse(in: CGRect(
            x: center.x - dotRadius * 1.8,
            y: center.y - dotRadius * 1.8,
            width: dotRadius * 3.6,
            height: dotRadius * 3.6
        ))

        // Inner dot
        ctx.setFillColor(
            UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.9).cgColor
        )
        ctx.fillEllipse(in: CGRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))

        ctx.restoreGState()
    }
}
