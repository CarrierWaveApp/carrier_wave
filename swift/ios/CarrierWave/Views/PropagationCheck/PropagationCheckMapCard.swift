import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - PropagationCheckMapCard

/// Map card for a saved propagation check: user grid as home, skimmers as
/// band-colored pins, geodesic arcs from home to each skimmer. Honors the
/// user's `shareMapStyle` preference — the custom styles (azimuthal /
/// midnight / warm / ocean / arctic / ember) render via the Rust
/// `renderShareMap` FFI, matching the activation share card and session
/// detail map. Adaptive / flat / globe styles use an interactive MapKit
/// `Map` with `.standardMapStyle`.
struct PropagationCheckMapCard: View {
    // MARK: Internal

    let check: PropagationCheck
    let enrichedSpots: [PropagationEnrichedSpot]

    var body: some View {
        let style = ShareMapStyle(rawValue: shareMapStyleRaw) ?? .adaptive
        Group {
            if style.usesCustomRenderer {
                themedMap(style: style)
            } else {
                interactiveMap
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    /// Re-render the themed image only when size, style, or pin count change.
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

    @AppStorage("shareMapStyle") private var shareMapStyleRaw = "adaptive"
    @Environment(\.displayScale) private var displayScale

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isWideSpan = false
    @State private var lastFittedCount: Int = -1
    @State private var themedImage: UIImage?

    private var homeCoord: CLLocationCoordinate2D? {
        MaidenheadConverter.coordinate(from: check.userGridUsed)
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var pins: [ResultPin] {
        enrichedSpots.compactMap(ResultPin.from)
    }

    // MARK: - Interactive (MapKit) flavor

    private var interactiveMap: some View {
        let pins = pins
        let homeCoord = homeCoord
        return Map(position: $cameraPosition) {
            if let home = homeCoord {
                ForEach(pins) { pin in
                    MapContentBuilders.geodesicArc(
                        from: home,
                        to: pin.coordinate,
                        color: BandColors.color(for: pin.band).opacity(0.7),
                        lineWidth: 1.5
                    )
                }
                Annotation("You", coordinate: home, anchor: .bottom) {
                    MapPinMarker(color: .accentColor, size: 12)
                }
            }
            ForEach(pins) { pin in
                Annotation(pin.skimmerCall, coordinate: pin.coordinate, anchor: .bottom) {
                    MapPinMarker(color: BandColors.color(for: pin.band))
                }
            }
        }
        .standardMapStyle(isWideSpan: isWideSpan)
        .task(id: pins.count) {
            guard pins.count > lastFittedCount else {
                return
            }
            lastFittedCount = pins.count

            let spotCoords = pins.map(\.coordinate)
            isWideSpan = ActivationMapHelpers.requiresGlobeView(
                qsoCoordinates: spotCoords,
                myCoordinate: homeCoord
            )
            cameraPosition = ActivationMapHelpers.mapCameraPosition(
                qsoCoordinates: spotCoords,
                myCoordinate: homeCoord
            )

            if isWideSpan {
                try? await Task.sleep(for: .seconds(0.5))
                nudgeCamera()
            }
        }
    }

    // MARK: - Themed (static) flavor

    private func themedMap(style: ShareMapStyle) -> some View {
        let pins = pins
        let homeCoord = homeCoord
        let ffiPins = pins.map { pin in
            ShareMapFFIRenderer.Pin.colored(
                pin.coordinate,
                color: UIColor(BandColors.color(for: pin.band))
            )
        }
        return GeometryReader { geo in
            ZStack {
                Color(uiColor: UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1))
                if let themedImage {
                    Image(uiImage: themedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .task(id: RenderKey(size: geo.size, style: style, count: pins.count)) {
                themedImage = await ShareMapFFIRenderer.render(
                    pins: ffiPins,
                    myCoordinate: homeCoord,
                    style: style,
                    size: geo.size,
                    scale: displayScale
                )
            }
        }
    }

    /// Nudge camera slightly to work around MapKit globe annotation rendering bug.
    /// Mirrors `SessionQSOMap.nudgeCamera()`.
    private func nudgeCamera() {
        guard let region = cameraPosition.region else {
            return
        }
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.center.latitude + 0.001,
                longitude: region.center.longitude
            ),
            span: region.span
        ))
    }
}

// MARK: - ResultPin

private struct ResultPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let band: String
    let skimmerCall: String

    static func from(_ spot: PropagationEnrichedSpot) -> ResultPin? {
        guard let coord = spot.coordinate else {
            return nil
        }
        return ResultPin(
            id: spot.id,
            coordinate: coord,
            band: spot.entry.band ?? "",
            skimmerCall: spot.entry.skimmerCall
        )
    }
}
