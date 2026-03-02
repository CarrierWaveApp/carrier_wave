// Sidebar Map View
//
// Lightweight map view for the iPad sidebar showing current session QSOs.
// Adapted from SessionMapPanelView without the dismiss header.

import CarrierWaveCore
import MapKit
import SwiftUI

// MARK: - SidebarMapView

struct SidebarMapView: View {
    // MARK: Internal

    let sessionQSOs: [QSO]
    let myGrid: String?
    var roveStops: [RoveStop] = []

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            Divider()

            if mappableQSOs.isEmpty, roveStopCoordinates.isEmpty {
                emptyView
            } else {
                mapContent
            }
        }
    }

    // MARK: Private

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var mappableQSOs: [QSO] {
        sessionQSOs.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return MaidenheadConverter.coordinate(from: grid) != nil
        }
    }

    private var myCoordinate: CLLocationCoordinate2D? {
        guard let grid = myGrid, grid.count >= 4 else {
            return nil
        }
        return MaidenheadConverter.coordinate(from: grid)
    }

    private var roveStopCoordinates: [(stop: RoveStop, coordinate: CLLocationCoordinate2D)] {
        roveStops.compactMap { stop in
            let grid = stop.myGrid ?? myGrid
            guard let grid, grid.count >= 4,
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            return (stop: stop, coordinate: coord)
        }
    }

    private var isRove: Bool {
        !roveStops.isEmpty
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack {
            Image(systemName: "map.fill")
                .foregroundStyle(.blue)

            if isRove {
                Text("\(roveStops.count) stops")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Text("\(mappableQSOs.count) QSOs mapped")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No QSOs with grid squares")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Map Content

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            ForEach(mappableQSOs) { qso in
                if let grid = qso.theirGrid,
                   let coordinate = MaidenheadConverter.coordinate(from: grid)
                {
                    qsoAnnotation(qso, coordinate: coordinate)
                }
            }

            // Rove stop markers
            ForEach(
                Array(roveStopCoordinates.enumerated()),
                id: \.element.stop.id
            ) { index, item in
                Annotation(
                    item.stop.parkReference,
                    coordinate: item.coordinate,
                    anchor: .bottom
                ) {
                    roveStopMarker(item.stop, index: index)
                }
            }

            // Route line between rove stops
            if roveStopCoordinates.count >= 2 {
                let coords = roveStopCoordinates.map(\.coordinate)
                MapPolyline(coordinates: coords)
                    .stroke(.green, style: StrokeStyle(
                        lineWidth: 3,
                        dash: [8, 4]
                    ))
            }

            // Geodesic paths from my location to each QSO
            if let myCoord = myCoordinate {
                ForEach(mappableQSOs) { qso in
                    if let grid = qso.theirGrid,
                       let theirCoord = MaidenheadConverter.coordinate(from: grid)
                    {
                        MapPolyline(
                            coordinates: geodesicPath(from: myCoord, to: theirCoord)
                        )
                        .stroke(.white.opacity(0.5), lineWidth: 2.5)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    private func roveStopMarker(_ stop: RoveStop, index: Int) -> some View {
        let primaryPark = ParkReference.split(stop.parkReference).first
            ?? stop.parkReference

        return VStack(spacing: 2) {
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

    // MARK: - Annotation Builders

    private func qsoAnnotation(
        _ qso: QSO,
        coordinate: CLLocationCoordinate2D
    ) -> some MapContent {
        Annotation(
            qso.callsign,
            coordinate: coordinate,
            anchor: .bottom
        ) {
            MapPinMarker(
                color: RSTColorHelper.color(
                    rstSent: qso.rstSent,
                    rstReceived: qso.rstReceived
                )
            )
        }
    }

    // MARK: - Geodesic Path

    private func geodesicPath(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        segments: Int = 50
    ) -> [CLLocationCoordinate2D] {
        var path: [CLLocationCoordinate2D] = []

        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let angularDistance =
            2
                * asin(
                    sqrt(
                        pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2)
                            * pow(sin((lon2 - lon1) / 2), 2)
                    )
                )

        for i in 0 ... segments {
            let fraction = Double(i) / Double(segments)
            let coeffA = sin((1 - fraction) * angularDistance)
                / sin(angularDistance)
            let coeffB = sin(fraction * angularDistance)
                / sin(angularDistance)

            let x = coeffA * cos(lat1) * cos(lon1)
                + coeffB * cos(lat2) * cos(lon2)
            let y = coeffA * cos(lat1) * sin(lon1)
                + coeffB * cos(lat2) * sin(lon2)
            let z = coeffA * sin(lat1) + coeffB * sin(lat2)

            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi

            path.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return path
    }
}
