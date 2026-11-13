// Activation Share Offline Map
//
// Deterministic vector fallback for the activation share card map, used
// when MKMapSnapshotter fails or times out (no connectivity in the field).
// Draws the same RST-coloured great-circle traces and pin markers the tile
// path draws, on the brag sheet's purple gradient with graticule lines, so
// the card keeps its exact layout and the operator can still save/share it.

import CarrierWaveCore
import CoreLocation
import UIKit

enum ActivationShareOfflineMap {
    // MARK: Internal

    static let caption = "Map imagery unavailable offline"

    /// Render the fallback map at `size` points (rasterised at `scale`).
    static func render(
        markers: [ShareMapMarker],
        myCoordinate: CLLocationCoordinate2D?,
        withoutLocationCount: Int,
        size: CGSize,
        scale: CGFloat
    ) -> UIImage {
        var coordinates = markers.map(\.coordinate)
        if let myCoordinate {
            coordinates.append(myCoordinate)
        }
        let viewport = BragSheetShareRenderer.computeViewport(coordinates: coordinates)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { context in
            let ctx = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)

            drawGradient(in: ctx, bounds: bounds)
            BragSheetShareRenderer.drawGridLines(ctx: ctx, size: size, viewport: viewport)

            if let myCoordinate {
                drawTraces(
                    ctx: ctx, size: size, viewport: viewport,
                    from: myCoordinate, markers: markers
                )
            }

            for marker in markers {
                let point = viewport.project(
                    marker.coordinate.latitude, marker.coordinate.longitude,
                    imageSize: size
                )
                ActivationShareRenderer.drawMarker(at: point, in: ctx, color: marker.rstColor)
            }

            if let myCoordinate {
                let point = viewport.project(
                    myCoordinate.latitude, myCoordinate.longitude, imageSize: size
                )
                drawOperatorMarker(at: point, in: ctx)
            }

            ActivationShareRenderer.drawWithoutLocationBadge(
                count: withoutLocationCount, in: ctx, size: size
            )
            drawCaption(in: ctx, size: size)
        }
    }

    // MARK: Private

    private static let gradientColors: [CGColor] = [
        UIColor(red: 0.10, green: 0.06, blue: 0.22, alpha: 1).cgColor,
        UIColor(red: 0.22, green: 0.11, blue: 0.38, alpha: 1).cgColor,
        UIColor(red: 0.12, green: 0.07, blue: 0.26, alpha: 1).cgColor,
    ]

    private static func drawGradient(in ctx: CGContext, bounds: CGRect) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: gradientColors as CFArray,
            locations: [0, 0.55, 1]
        ) else {
            ctx.setFillColor(gradientColors[0])
            ctx.fill(bounds)
            return
        }
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.minX, y: bounds.minY),
            end: CGPoint(x: bounds.maxX, y: bounds.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    /// RST-coloured great-circle paths from the operator to every contact,
    /// projected through the same viewport as the pins.
    private static func drawTraces(
        ctx: CGContext,
        size: CGSize,
        viewport: BragSheetShareRenderer.MapViewport,
        from origin: CLLocationCoordinate2D,
        markers: [ShareMapMarker]
    ) {
        ctx.saveGState()
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        for marker in markers {
            let segments = ActivationMapHelpers.geodesicSegments(
                from: origin, to: marker.coordinate, segments: 30
            )
            ctx.setStrokeColor(marker.rstColor.withAlphaComponent(0.6).cgColor)
            for segment in segments where segment.count >= 2 {
                let points = segment.map {
                    viewport.project($0.latitude, $0.longitude, imageSize: size)
                }
                ctx.move(to: points[0])
                for point in points.dropFirst() {
                    ctx.addLine(to: point)
                }
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    private static func drawOperatorMarker(at point: CGPoint, in ctx: CGContext) {
        let radius: CGFloat = 4
        ctx.saveGState()
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: point.x - radius, y: point.y - radius,
            width: radius * 2, height: radius * 2
        ))
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: CGRect(
            x: point.x - radius * 2, y: point.y - radius * 2,
            width: radius * 4, height: radius * 4
        ))
        ctx.restoreGState()
    }

    private static func drawCaption(in ctx: CGContext, size: CGSize) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.55),
        ]
        let text = caption as NSString
        let textSize = text.size(withAttributes: attrs)
        let origin = CGPoint(
            x: size.width - textSize.width - 8,
            y: size.height - textSize.height - 6
        )
        UIGraphicsPushContext(ctx)
        text.draw(at: origin, withAttributes: attrs)
        UIGraphicsPopContext()
    }
}
