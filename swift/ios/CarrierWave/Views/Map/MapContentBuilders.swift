// Map Content Builders
//
// Shared @MapContentBuilder functions for composing common map elements
// (geodesic arcs, QSO annotations, rove stops, my-location marker) across
// all map views. Eliminates duplicated MapContent patterns.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - MapContentBuilders

enum MapContentBuilders {
    // MARK: - Geodesic Arcs

    /// Renders a single geodesic (great circle) arc between two coordinates,
    /// split at the antimeridian so MapKit renders correctly.
    @MapContentBuilder
    static func geodesicArc(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        color: Color = .white.opacity(0.5),
        lineWidth: CGFloat = 2.5
    ) -> some MapContent {
        let segments = ActivationMapHelpers.geodesicSegments(
            from: start, to: end
        )
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            MapPolyline(coordinates: segment)
                .stroke(color, lineWidth: lineWidth)
        }
    }

    /// Renders geodesic arcs from a home coordinate to each QSO that has a valid grid.
    @MapContentBuilder
    static func geodesicArcs(
        from myCoordinate: CLLocationCoordinate2D,
        to qsos: [QSO],
        color: Color = .white.opacity(0.5),
        lineWidth: CGFloat = 2.5
    ) -> some MapContent {
        ForEach(qsos) { qso in
            if let grid = qso.theirGrid,
               let theirFfiCoord = maidenheadCoordinate(grid: grid)
            {
                geodesicArc(
                    from: myCoordinate,
                    to: CLLocationCoordinate2D(latitude: theirFfiCoord.latitude, longitude: theirFfiCoord.longitude),
                    color: color, lineWidth: lineWidth
                )
            }
        }
    }

    // MARK: - QSO Annotations

    /// Renders RST-colored pin annotations for QSOs with valid grid squares.
    @MapContentBuilder
    static func qsoAnnotations(for qsos: [QSO]) -> some MapContent {
        ForEach(qsos) { qso in
            if let grid = qso.theirGrid,
               let ffiCoordinate = maidenheadCoordinate(grid: grid)
            {
                let coordinate = CLLocationCoordinate2D(
                    latitude: ffiCoordinate.latitude, longitude: ffiCoordinate.longitude
                )
                Annotation(
                    qso.callsign, coordinate: coordinate, anchor: .bottom
                ) {
                    MapPinMarker(
                        color: RSTColorHelper.color(
                            rstSent: qso.rstSent,
                            rstReceived: qso.rstReceived
                        )
                    )
                }
            }
        }
    }

    // MARK: - My Location Marker

    /// Renders the operator's location as a blue pin marker.
    @MapContentBuilder
    static func myLocationMarker(
        at coordinate: CLLocationCoordinate2D,
        label: String = "Me"
    ) -> some MapContent {
        Annotation(label, coordinate: coordinate, anchor: .bottom) {
            MapPinMarker(color: .blue, size: 12)
        }
    }

    // MARK: - Rove Stop Overlay

    /// Renders numbered rove stop markers with a dashed route line between them.
    @MapContentBuilder
    static func roveStopOverlay(
        stops: [(stop: RoveStop, coordinate: CLLocationCoordinate2D)]
    ) -> some MapContent {
        ForEach(Array(stops.enumerated()), id: \.element.stop.id) { index, item in
            Annotation(
                item.stop.parkReference,
                coordinate: item.coordinate,
                anchor: .bottom
            ) {
                RoveStopMarker(stop: item.stop, index: index)
            }
        }

        if stops.count >= 2 {
            let coords = stops.map(\.coordinate)
            MapPolyline(coordinates: coords)
                .stroke(.green, style: StrokeStyle(
                    lineWidth: 3,
                    dash: [8, 4]
                ))
        }
    }
}

// MARK: - RoveStopMarker

/// Shared rove stop marker showing park reference and stop number.
struct RoveStopMarker: View {
    let stop: RoveStop
    let index: Int

    var body: some View {
        let primaryPark = ParkReference.split(stop.parkReference).first
            ?? stop.parkReference

        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(stop.isActive ? Color.green : Color(.systemGray3))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }

            Text(primaryPark)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - View+StandardMapStyle

extension View {
    /// Applies the user's preferred map style, switching to globe/imagery
    /// for wide geographic spans when the style supports it.
    func standardMapStyle(isWideSpan: Bool = false) -> some View {
        modifier(StandardMapStyleModifier(isWideSpan: isWideSpan))
    }
}

// MARK: - StandardMapStyleModifier

private struct StandardMapStyleModifier: ViewModifier {
    // MARK: Internal

    let isWideSpan: Bool

    func body(content: Content) -> some View {
        let style = ShareMapStyle(rawValue: shareMapStyleRaw) ?? .adaptive
        let useGlobe = style.shouldUseGlobe(isWideSpan: isWideSpan)
        content.mapStyle(useGlobe
            ? .imagery(elevation: .realistic)
            : .standard(elevation: .realistic))
    }

    // MARK: Private

    @AppStorage("shareMapStyle") private var shareMapStyleRaw = "adaptive"
}
