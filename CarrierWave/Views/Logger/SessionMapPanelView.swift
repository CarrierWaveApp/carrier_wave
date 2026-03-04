// Session Map Panel View for Logger
//
// Displays a map of QSOs from the current logging session.
// For rove sessions, also shows route lines between park stops.

import CarrierWaveData
import MapKit
import SwiftUI

// MARK: - SessionMapPanelView

struct SessionMapPanelView: View {
    // MARK: Internal

    /// QSOs for the current session (passed in to avoid full table scan with @Query)
    let sessionQSOs: [QSO]
    let myGrid: String?
    /// Rove stops for route display (empty for non-rove sessions)
    var roveStops: [RoveStop] = []
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if sessionQSOs.isEmpty, roveStopCoordinates.isEmpty {
                emptyView
            } else {
                mapContent
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }

    // MARK: Private

    @State private var cameraPosition: MapCameraPosition = .automatic

    /// QSOs with valid grid squares
    private var mappableQSOs: [QSO] {
        sessionQSOs.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return MaidenheadConverter.coordinate(from: grid) != nil
        }
    }

    /// My coordinate from grid
    private var myCoordinate: CLLocationCoordinate2D? {
        guard let grid = myGrid, grid.count >= 4 else {
            return nil
        }
        return MaidenheadConverter.coordinate(from: grid)
    }

    /// Coordinates for rove stops, falling back to session grid if stop has no grid
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "map.fill")
                .foregroundStyle(.blue)

            Text(isRove ? "Rove Map" : "Session Map")
                .font(.headline)

            Spacer()

            if isRove {
                Text("\(roveStops.count) stops")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Text("\(mappableQSOs.count) QSOs")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - Content Views

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No QSOs with grid squares")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            // Show markers for each QSO with a grid
            ForEach(mappableQSOs) { qso in
                if let grid = qso.theirGrid,
                   let coordinate = MaidenheadConverter.coordinate(from: grid)
                {
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
            }

            // Rove stop markers
            ForEach(
                Array(roveStopCoordinates.enumerated()), id: \.element.stop.id
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

            // Draw geodesic paths from my location to each QSO
            if let myCoord = myCoordinate {
                ForEach(mappableQSOs) { qso in
                    if let grid = qso.theirGrid,
                       let theirCoord = MaidenheadConverter.coordinate(
                           from: grid
                       )
                    {
                        MapPolyline(
                            coordinates: geodesicPath(
                                from: myCoord, to: theirCoord
                            )
                        )
                        .stroke(.white.opacity(0.5), lineWidth: 2.5)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 250)
    }

    /// Marker for a rove stop showing park reference and stop number
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

    /// Generate a geodesic (great circle) path between two coordinates
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
