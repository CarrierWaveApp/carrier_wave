// Brag Sheet Share Renderer - Drawing Helpers
//
// Extracted drawing methods for map rendering: grid lines,
// geodesic trace lines, dot markers, and day/night terminator overlay.

import CarrierWaveData
import CoreGraphics
import CoreLocation
import Foundation
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

    /// Saturated magenta for trace lines on the standard Apple tile map.
    /// Chosen to read clearly against the muted blue/beige Apple palette.
    static let traceLineColor = UIColor(
        red: 0.925, green: 0.31, blue: 0.67, alpha: 0.85
    )

    /// Draw geodesic trace lines from operator location to each cluster.
    /// Uses `geodesicSegments` (not `geodesicPath`) so that lines crossing
    /// ±180° don't jump across antimeridian-spanning viewports.
    static func drawTraceLines(
        ctx: CGContext, size: CGSize, viewport: MapViewport,
        from origin: CLLocationCoordinate2D,
        clusters: [BragSheetMapCluster]
    ) {
        ctx.setStrokeColor(traceLineColor.cgColor)
        ctx.setLineWidth(1.8)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for cluster in clusters {
            let segments = ActivationMapHelpers.geodesicSegments(
                from: origin, to: cluster.coordinate, segments: 40
            )
            for segment in segments where segment.count >= 2 {
                let firstPt = viewport.project(
                    segment[0].latitude, segment[0].longitude, imageSize: size
                )
                ctx.move(to: firstPt)
                for coord in segment.dropFirst() {
                    let pt = viewport.project(
                        coord.latitude, coord.longitude, imageSize: size
                    )
                    ctx.addLine(to: pt)
                }
                ctx.strokePath()
            }
        }
    }

    // MARK: - Pin Colors

    static func pinColor(for count: Int) -> UIColor {
        switch count {
        case 1 ... 5: UIColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1)
        case 6 ... 20: UIColor(red: 0.90, green: 0.85, blue: 0.45, alpha: 1)
        case 21 ... 50: UIColor(red: 0.90, green: 0.65, blue: 0.35, alpha: 1)
        default: UIColor(red: 0.90, green: 0.45, blue: 0.40, alpha: 1)
        }
    }

    // MARK: - Dot Marker (MKMapSnapshotter path)

    /// Draw a filled dot with a white halo at the given point.
    /// Used on the Apple tile map path where pin stems add visual clutter;
    /// the halo keeps the dot readable against busy tile backgrounds.
    static func drawDotMarker(
        at point: CGPoint, in ctx: CGContext, count: Int
    ) {
        let color = pinColor(for: count)
        let radius: CGFloat = 3.5
        let halo: CGFloat = 0.9

        ctx.saveGState()
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: point.x - radius - halo,
            y: point.y - radius - halo,
            width: (radius + halo) * 2,
            height: (radius + halo) * 2
        ))
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        ctx.restoreGState()
    }

    // MARK: - Day/Night Terminator

    /// Overlay the current solar terminator ("gray line") on the map.
    ///
    /// Darkens the night side of the Earth with a soft twilight transition,
    /// giving the share card a sense of temporal place. Subsolar point is
    /// computed from `date` (typically `Date()` at render time). Accuracy
    /// is ±1° which is sufficient for visual display.
    static func drawTerminator(
        size: CGSize, viewport: BragSheetShareRenderer.MapViewport, date: Date
    ) {
        guard let cgImage = terminatorMaskImage(viewport: viewport, date: date) else {
            return
        }
        UIImage(cgImage: cgImage).draw(
            in: CGRect(origin: .zero, size: size),
            blendMode: .normal,
            alpha: 1.0
        )
    }

    /// Build a low-resolution RGBA alpha mask where alpha varies from 0 (day)
    /// to ~38% (night) based on the solar altitude at each lat/lon cell.
    /// The caller renders this with bilinear interpolation for smoothness.
    private static func terminatorMaskImage(
        viewport: BragSheetShareRenderer.MapViewport, date: Date
    ) -> CGImage? {
        let latRange = viewport.maxLat - viewport.minLat
        let lonRange = viewport.maxLon - viewport.minLon
        guard latRange > 0, lonRange > 0 else {
            return nil
        }

        let sun = SubsolarPoint(date: date)
        let maskWidth = 96
        let maskHeight = 52
        let pixels = terminatorAlphaPixels(
            width: maskWidth, height: maskHeight,
            viewport: viewport, sun: sun
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        return CGImage(
            width: maskWidth, height: maskHeight,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: maskWidth * 4,
            space: colorSpace, bitmapInfo: bitmapInfo,
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Fill an RGBA byte buffer where R=G=B=0 and A encodes twilight darkness.
    private static func terminatorAlphaPixels(
        width: Int, height: Int,
        viewport: BragSheetShareRenderer.MapViewport,
        sun: SubsolarPoint
    ) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let latRange = viewport.maxLat - viewport.minLat
        let lonRange = viewport.maxLon - viewport.minLon

        for yIdx in 0 ..< height {
            let yFrac = (Double(yIdx) + 0.5) / Double(height)
            let lat = viewport.maxLat - yFrac * latRange
            let latRad = lat * .pi / 180
            let sinLat = sin(latRad)
            let cosLat = cos(latRad)
            for xIdx in 0 ..< width {
                let xFrac = (Double(xIdx) + 0.5) / Double(width)
                let lonDeg = viewport.minLon + xFrac * lonRange
                let lonRad = lonDeg * .pi / 180
                let cosZen = sinLat * sun.sinDecl
                    + cosLat * sun.cosDecl * cos(lonRad - sun.subsolarLonRad)
                // Twilight band: +0.08 (full day) → -0.08 (full night).
                let twilight = max(0.0, min(1.0, (0.08 - cosZen) / 0.16))
                let alpha = UInt8(twilight * 0.38 * 255)
                pixels[(yIdx * width + xIdx) * 4 + 3] = alpha
            }
        }
        return pixels
    }

    /// Precomputed solar trig values for a given moment. ±1° accuracy.
    struct SubsolarPoint {
        // MARK: Lifecycle

        init(date: Date) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC") ?? .current
            let comp = cal.dateComponents(
                [.dayOfYear, .hour, .minute, .second], from: date
            )
            let dayOfYear = Double(comp.dayOfYear ?? 1)
            let utcHours = Double(comp.hour ?? 0)
                + Double(comp.minute ?? 0) / 60
                + Double(comp.second ?? 0) / 3_600
            let declDeg = 23.44 * sin(
                (360.0 / 365.25) * (dayOfYear - 81) * .pi / 180
            )
            let declRad = declDeg * .pi / 180
            sinDecl = sin(declRad)
            cosDecl = cos(declRad)
            subsolarLonRad = (-15.0 * (utcHours - 12.0)) * .pi / 180
        }

        // MARK: Internal

        let sinDecl: Double
        let cosDecl: Double
        let subsolarLonRad: Double
    }
}
