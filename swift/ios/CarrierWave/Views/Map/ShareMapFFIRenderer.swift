// Share Map FFI Renderer
//
// Host-side bridge onto the Rust `renderShareMap` FFI. The six custom
// ShareMapStyle themes (azimuthal, midnight, warm, ocean, arctic, ember)
// used to be drawn by the CoreGraphics `FlatMapRenderer` /
// `AzimuthalMapRenderer`; those rasterizers were deleted in map port
// phase D. This type assembles `FfiShareMapInput` from the same pin /
// cluster / trace / center data the orchestrators already collect, runs
// the render off the main thread, and composites the azimuthal range-ring
// labels back into the PNG (Rust returns their anchors; text stays a
// host-side concern so we keep the system font + kerning).
//
// The MapKit styles (adaptive / flat / globe) are NOT handled here — they
// stay on their MKMapSnapshotter paths in the orchestrators.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import UIKit

// MARK: - ShareMapStyle → FFI mapping

extension ShareMapStyle {
    /// The Rust share-map style for this preference, or `nil` for the
    /// MapKit-backed styles (adaptive / flat / globe) that never touch the
    /// FFI rasterizer. This is the single place the mapping lives.
    var ffiStyle: FfiShareMapStyle? {
        switch self {
        case .azimuthal: .azimuthal
        case .midnight: .midnight
        case .warm: .warm
        case .ocean: .ocean
        case .arctic: .arctic
        case .ember: .ember
        case .adaptive,
             .flat,
             .globe: nil
        }
    }
}

// MARK: - ShareMapFFIRenderer

/// Renders the custom share-map styles via the Rust `renderShareMap` FFI.
@MainActor
enum ShareMapFFIRenderer {
    // MARK: Internal

    /// A pin to render. RST / band-colored pins carry an explicit color
    /// (`Rgba` mode); brag-sheet clusters carry a count (`Count` mode, the
    /// count→color ramp lives in Rust).
    struct Pin {
        let coordinate: CLLocationCoordinate2D
        /// Set for count-ramp pins; `nil` for explicitly-colored pins.
        let count: Int?
        /// Set for explicitly-colored pins; `nil` for count-ramp pins.
        let color: UIColor?

        static func colored(_ coordinate: CLLocationCoordinate2D, color: UIColor) -> Pin {
            Pin(coordinate: coordinate, count: nil, color: color)
        }

        static func counted(_ coordinate: CLLocationCoordinate2D, count: Int) -> Pin {
            Pin(coordinate: coordinate, count: count, color: nil)
        }
    }

    /// Render the given pins for `style` (must be a custom style — callers
    /// gate on `style.ffiStyle != nil`). `size` is in points; the PNG is
    /// rasterized at `size * scale`. Trace lines are drawn from
    /// `myCoordinate` (when present) to every pin, and the operator QTH
    /// center marker is drawn when `myCoordinate` is set. Returns `nil` when
    /// the style is not a custom style or the FFI render fails.
    /// `qthCentered` frames flat styles on the operator QTH (brag sheets)
    /// instead of the bounds midpoint; it has no effect without a QTH.
    static func render(
        pins: [Pin],
        myCoordinate: CLLocationCoordinate2D?,
        style: ShareMapStyle,
        size: CGSize,
        scale: CGFloat,
        qthCentered: Bool = false
    ) async -> UIImage? {
        guard let ffiStyle = style.ffiStyle else {
            return nil
        }

        let input = buildInput(
            pins: pins, myCoordinate: myCoordinate,
            ffiStyle: ffiStyle,
            pixelSize: CGSize(width: size.width * scale, height: size.height * scale),
            qthCentered: qthCentered
        )

        let rendered: FfiShareMapImage? = await Task.detached {
            try? renderShareMap(style: ffiStyle, input: input)
        }.value

        guard let rendered,
              let baseImage = UIImage(data: Data(rendered.pngBytes))
        else {
            return nil
        }

        return overlayRingLabels(rendered.ringLabels, on: baseImage)
    }

    // MARK: Private

    /// The viewport center + spans to feed `FfiShareMapInput`.
    private struct ViewportFrame {
        let centerLat: Double?
        let centerLon: Double?
        let latSpan: Double
        let lonSpan: Double
    }

    /// Range-ring label font — matches the deleted `AzimuthalMapRenderer`
    /// `drawRingLabel` (7pt system regular, white at 0.2 alpha).
    private static let ringLabelFont = UIFont.systemFont(ofSize: 7, weight: .regular)
    private static let ringLabelColor = UIColor.white.withAlphaComponent(0.2)

    /// Assemble the `FfiShareMapInput` from host-side pins. Colored pins map
    /// to the `Rgba` pin mode; counted pins to the `Count` ramp. Traces run
    /// from `myCoordinate` (when present) to every pin.
    ///
    /// Viewport framing differs by projection:
    /// - **flat** styles use `computeFlatShareViewport` (the recovered
    ///   `FlatMapRenderer.computeViewport`) over the operator QTH + every pin,
    ///   giving a bounds-midpoint center + aspect-fit spans.
    /// - **azimuthal** centers on the operator QTH (the projection center) and
    ///   ignores the spans; callers only reach this path when `myCoordinate`
    ///   is non-nil.
    private static func buildInput(
        pins: [Pin],
        myCoordinate: CLLocationCoordinate2D?,
        ffiStyle: FfiShareMapStyle,
        pixelSize: CGSize,
        qthCentered: Bool
    ) -> FfiShareMapInput {
        let sharePins = pins.map { pin -> FfiSharePin in
            if let color = pin.color {
                let rgba = color.shareMapComponents
                return FfiSharePin(
                    lat: pin.coordinate.latitude,
                    lon: pin.coordinate.longitude,
                    kind: .rgba,
                    count: 0,
                    red: rgba.red, green: rgba.green,
                    blue: rgba.blue, alpha: rgba.alpha
                )
            }
            return FfiSharePin(
                lat: pin.coordinate.latitude,
                lon: pin.coordinate.longitude,
                kind: .count,
                count: UInt32(max(0, pin.count ?? 0)),
                red: 0, green: 0, blue: 0, alpha: 0
            )
        }

        let traces: [FfiShareTrace] =
            if let origin = myCoordinate {
                pins.map { pin in
                    FfiShareTrace(
                        fromLat: origin.latitude, fromLon: origin.longitude,
                        toLat: pin.coordinate.latitude, toLon: pin.coordinate.longitude
                    )
                }
            } else {
                []
            }

        let width = UInt32(max(1, pixelSize.width.rounded()))
        let height = UInt32(max(1, pixelSize.height.rounded()))
        let frame = viewportFrame(
            pins: pins, myCoordinate: myCoordinate,
            ffiStyle: ffiStyle, pixels: (width, height),
            qthCentered: qthCentered
        )

        return FfiShareMapInput(
            width: width,
            height: height,
            centerLat: frame.centerLat,
            centerLon: frame.centerLon,
            centerGrid: nil,
            latSpan: frame.latSpan,
            lonSpan: frame.lonSpan,
            pins: sharePins,
            traces: traces,
            showCenterMarker: myCoordinate != nil
        )
    }

    /// Resolve the viewport center + spans for the given style.
    ///
    /// Flat styles frame via the recovered `computeFlatShareViewport` (bounds
    /// midpoint of the operator QTH + every pin, aspect-fit to the image).
    /// Azimuthal centers on the operator QTH (its projection center) and
    /// ignores the spans, so those are left at zero.
    private static func viewportFrame(
        pins: [Pin],
        myCoordinate: CLLocationCoordinate2D?,
        ffiStyle: FfiShareMapStyle,
        pixels: (width: UInt32, height: UInt32),
        qthCentered: Bool
    ) -> ViewportFrame {
        guard ffiStyle != .azimuthal else {
            return ViewportFrame(
                centerLat: myCoordinate?.latitude, centerLon: myCoordinate?.longitude,
                latSpan: 0, lonSpan: 0
            )
        }
        if qthCentered, let origin = myCoordinate,
           let region = ActivationMapHelpers.qthCenteredFlatViewport(
               qsoCoordinates: pins.map(\.coordinate),
               myCoordinate: origin,
               aspect: Double(pixels.width) / Double(pixels.height)
           )
        {
            return ViewportFrame(
                centerLat: region.center.latitude, centerLon: region.center.longitude,
                latSpan: region.span.latitudeDelta, lonSpan: region.span.longitudeDelta
            )
        }
        var coords = pins.map {
            FfiCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        if let origin = myCoordinate {
            coords.append(FfiCoordinate(latitude: origin.latitude, longitude: origin.longitude))
        }
        let viewport = computeFlatShareViewport(coords: coords, width: pixels.width, height: pixels.height)
        return ViewportFrame(
            centerLat: viewport.centerLat, centerLon: viewport.centerLon,
            latSpan: viewport.latSpan, lonSpan: viewport.lonSpan
        )
    }

    /// Composite the azimuthal range-ring labels into the PNG.
    ///
    /// Anchor contract (from `cw_domain::share_render::RingLabel`): `x` is
    /// the horizontal center of the text and `y` is the ring's top point —
    /// text renders *above* `y`. Coordinates are in the PNG's pixel space,
    /// so we draw at the image's native scale (1.0) and size.
    private static func overlayRingLabels(
        _ labels: [FfiRingLabel], on image: UIImage
    ) -> UIImage {
        guard !labels.isEmpty else {
            return image
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { _ in
            image.draw(at: .zero)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: ringLabelFont,
                .foregroundColor: ringLabelColor,
            ]
            for label in labels {
                let text = label.text as NSString
                let textSize = text.size(withAttributes: attrs)
                // `x` centers the text; `y` is the ring top, text sits above.
                let origin = CGPoint(
                    x: CGFloat(label.x) - textSize.width / 2,
                    y: CGFloat(label.y) - textSize.height - 1
                )
                guard origin.y > 0 else {
                    continue
                }
                text.draw(at: origin, withAttributes: attrs)
            }
        }
    }
}

// MARK: - ShareMapRGBA

/// Straight (non-premultiplied) sRGB components in `0.0...1.0`, for the
/// `FfiSharePin` `Rgba` pin mode.
struct ShareMapRGBA {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float
}

extension UIColor {
    var shareMapComponents: ShareMapRGBA {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return ShareMapRGBA(
            red: Float(red), green: Float(green),
            blue: Float(blue), alpha: Float(alpha)
        )
    }
}
