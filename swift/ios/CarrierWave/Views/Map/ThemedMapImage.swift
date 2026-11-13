import CarrierWaveData
import MapKit
import SwiftUI

// MARK: - ThemedMapImage

/// Renders a static map image via the Rust `renderShareMap` FFI for the
/// custom `ShareMapStyle` themes (azimuthal, midnight, ocean, arctic, ember,
/// warm). Use in place of MapKit `Map` views when `style.usesCustomRenderer`
/// is true. The render runs off the main thread; the view shows the themed
/// background color until the image is ready.
struct ThemedMapImage: View {
    // MARK: Internal

    let coordinates: [CLLocationCoordinate2D]
    let myCoordinate: CLLocationCoordinate2D?
    let style: ShareMapStyle
    /// Optional per-coordinate pin colors (parallel to `coordinates`).
    /// When `nil`, all pins render in the default blue.
    var pinColors: [UIColor]?
    /// Frame flat styles on the operator QTH instead of the bounds midpoint
    /// (brag sheets).
    var qthCentered = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(uiColor: UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .task(id: RenderKey(size: geo.size, style: style, count: coordinates.count)) {
                image = await renderImage(size: geo.size)
            }
        }
    }

    // MARK: Private

    /// Re-render when the layout size, style, or coordinate count changes.
    /// `style` is part of the key so a live style switch re-renders — matches
    /// `PropagationCheckMapCard.RenderKey`.
    private struct RenderKey: Equatable {
        // MARK: Lifecycle

        init(size: CGSize, style: ShareMapStyle, count: Int) {
            width = size.width
            height = size.height
            self.style = style
            self.count = count
        }

        // MARK: Internal

        let width: CGFloat
        let height: CGFloat
        let style: ShareMapStyle
        let count: Int
    }

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private func renderImage(size: CGSize) async -> UIImage? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let colors = pinColors
        let pins = coordinates.enumerated().map { index, coord in
            let color = (colors != nil && index < colors!.count)
                ? colors![index] : .systemBlue
            return ShareMapFFIRenderer.Pin.colored(coord, color: color)
        }
        return await ShareMapFFIRenderer.render(
            pins: pins,
            myCoordinate: myCoordinate,
            style: style,
            size: size,
            scale: displayScale,
            qthCentered: qthCentered
        )
    }
}
