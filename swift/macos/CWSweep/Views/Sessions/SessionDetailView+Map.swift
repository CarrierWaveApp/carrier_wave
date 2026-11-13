// Session Detail View - Map Section
//
// Map rendering for session detail, with dateline-aware camera positioning
// and satellite imagery for wide-span (>90°) QSO distributions.

import CarrierWaveCore
import CarrierWaveData
import MapKit
import SwiftUI

// MARK: - Map Section

extension SessionDetailView {
    @ViewBuilder
    var mapSection: some View {
        if !mappableQSOs.isEmpty {
            Section("Map") {
                mapPreview(mappable: mappableQSOs)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
    }

    // MARK: - Map Preview

    private var myCoordinate: CLLocationCoordinate2D? {
        guard let grid = session.myGrid, grid.count >= 4,
              let coord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    private func mapPreview(mappable: [QSO]) -> some View {
        let myCoord = myCoordinate
        let cachedPaths = mapPaths

        return ZStack(alignment: .bottomTrailing) {
            mapContent(mappable: mappable, myCoord: myCoord, paths: cachedPaths)
                .mapStyle(isWideSpan
                    ? .imagery(elevation: .realistic)
                    : .standard(elevation: .realistic))
                .allowsHitTesting(false)
                .frame(height: 200)
                .task(id: mappable.count) {
                    let result = computeMapCamera(
                        mappable: mappable, myCoordinate: myCoord
                    )
                    isWideSpan = result.isWide
                    mapPosition = result.position
                }

            qsoCountBadge(count: mappable.count)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session map with \(mappable.count) QSOs")
    }

    private func mapContent(
        mappable: [QSO],
        myCoord: CLLocationCoordinate2D?,
        paths: [UUID: [CLLocationCoordinate2D]]
    ) -> some View {
        Map(position: $mapPosition, interactionModes: []) {
            ForEach(mappable) { qso in
                if let grid = qso.theirGrid,
                   let coord = MaidenheadConverter.coordinate(from: grid)
                {
                    let clCoord = CLLocationCoordinate2D(
                        latitude: coord.latitude, longitude: coord.longitude
                    )
                    Annotation(qso.callsign, coordinate: clCoord, anchor: .bottom) {
                        SessionMapPin(color: .orange)
                    }
                }
            }
            if let myCoord {
                Annotation("Me", coordinate: myCoord, anchor: .bottom) {
                    SessionMapPin(color: .blue, size: 12)
                }
                ForEach(mappable) { qso in
                    if let path = paths[qso.id] {
                        MapPolyline(coordinates: path)
                            .stroke(.white.opacity(0.5), lineWidth: 2.5)
                    }
                }
            }
        }
    }

    private func qsoCountBadge(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "map.fill")
            Text("\(count) QSOs")
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
        .padding(8)
    }

    // MARK: - Geodesic Path

    /// Great-circle interpolation for geodesic lines on the map
    static func geodesicPath(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        segments: Int
    ) -> [CLLocationCoordinate2D] {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180

        let dLat = lat2 - lat1
        let dLon = lon2 - lon1
        let halfA = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let angularDist = 2 * atan2(sqrt(halfA), sqrt(1 - halfA))

        guard angularDist > 0.001 else {
            return [from, to]
        }

        var points: [CLLocationCoordinate2D] = []
        points.reserveCapacity(segments + 1)

        for i in 0 ... segments {
            let frac = Double(i) / Double(segments)
            let aFrac = sin((1 - frac) * angularDist) / sin(angularDist)
            let bFrac = sin(frac * angularDist) / sin(angularDist)

            let x = aFrac * cos(lat1) * cos(lon1) + bFrac * cos(lat2) * cos(lon2)
            let y = aFrac * cos(lat1) * sin(lon1) + bFrac * cos(lat2) * sin(lon2)
            let z = aFrac * sin(lat1) + bFrac * sin(lat2)

            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi

            points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return points
    }

    // MARK: - Camera Position

    /// Compute camera position and wide-span flag for session map.
    /// Dateline-aware: uses shorter of direct vs dateline-crossing span.
    private func computeMapCamera(
        mappable: [QSO],
        myCoordinate: CLLocationCoordinate2D?
    ) -> (position: MapCameraPosition, isWide: Bool) {
        var allCoords: [CLLocationCoordinate2D] = mappable.compactMap { qso in
            guard let grid = qso.theirGrid,
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        }
        if let myCoord = myCoordinate {
            allCoords.append(myCoord)
        }

        guard !allCoords.isEmpty else {
            return (.automatic, false)
        }

        let lats = allCoords.map(\.latitude)
        let lons = allCoords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else {
            return (.automatic, false)
        }

        let directSpan = maxLon - minLon
        let datelineSpan = 360 - directSpan
        let crossesDateline = datelineSpan < directSpan
        let lonSpan = crossesDateline ? datelineSpan : directSpan
        let latSpan = maxLat - minLat

        let isWide = max(latSpan, lonSpan) > 90

        let centerLat = (minLat + maxLat) / 2
        let centerLon: Double
        if crossesDateline {
            let raw = maxLon + datelineSpan / 2
            centerLon = raw > 180 ? raw - 360 : raw
        } else {
            centerLon = (minLon + maxLon) / 2
        }

        let padding: Double = isWide ? 1.5 : 1.3
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: centerLat, longitude: centerLon
            ),
            span: MKCoordinateSpan(
                latitudeDelta: min(max(latSpan, 5) * padding, 180),
                longitudeDelta: min(max(lonSpan, 5) * padding, 360)
            )
        )
        return (.region(region), isWide)
    }
}
