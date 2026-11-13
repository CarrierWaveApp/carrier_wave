import CarrierWaveCore
import MapKit
import SwiftUI

// MARK: - ActivationMapPane + Camera & Geodesic

extension ActivationMapPane {
    func updateCamera() {
        switch mapState {
        case .idle,
             .lookupPending:
            updateIdleCamera()
        case let .geodesicFocus(grid):
            updateGeodesicCamera(theirGrid: grid)
        }
    }

    func updateIdleCamera() {
        let qsoCoords = plottableQSOs.map(\.coordinate)
        var allCoords = qsoCoords
        if let user = userCoordinate {
            allCoords.append(user)
        }

        guard !allCoords.isEmpty else {
            cameraPosition = .automatic
            return
        }

        if allCoords.count == 1 {
            let center = allCoords[0]
            cameraPosition = .region(MKCoordinateRegion(
                center: center,
                latitudinalMeters: 3_000_000,
                longitudinalMeters: 3_000_000
            ))
            return
        }

        let region = boundingRegion(for: allCoords, padding: 1.3)
        cameraPosition = .region(region)
    }

    func updateGeodesicCamera(theirGrid: String) {
        guard let userCoord = userCoordinate,
              let theirCoordRaw = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            updateIdleCamera()
            return
        }
        let theirCoord = CLLocationCoordinate2D(
            latitude: theirCoordRaw.latitude, longitude: theirCoordRaw.longitude
        )
        let region = boundingRegion(for: [userCoord, theirCoord], padding: 1.4)
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(region)
        }
    }

    /// Great-circle interpolation matching Carrier Wave iOS style.
    func geodesicPath(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        segments: Int = 30
    ) -> [CLLocationCoordinate2D] {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let angularDist =
            2 * asin(sqrt(
                pow(sin((lat2 - lat1) / 2), 2)
                    + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)
            ))

        guard angularDist > 0.001 else {
            return [start, end]
        }

        var points: [CLLocationCoordinate2D] = []
        points.reserveCapacity(segments + 1)

        for idx in 0 ... segments {
            let frac = Double(idx) / Double(segments)
            let coeffA = sin((1 - frac) * angularDist) / sin(angularDist)
            let coeffB = sin(frac * angularDist) / sin(angularDist)

            let px = coeffA * cos(lat1) * cos(lon1) + coeffB * cos(lat2) * cos(lon2)
            let py = coeffA * cos(lat1) * sin(lon1) + coeffB * cos(lat2) * sin(lon2)
            let pz = coeffA * sin(lat1) + coeffB * sin(lat2)

            let lat = atan2(pz, sqrt(px * px + py * py)) * 180 / .pi
            let lon = atan2(py, px) * 180 / .pi
            points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return points
    }

    func boundingRegion(
        for coords: [CLLocationCoordinate2D], padding: Double
    ) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * padding, 2),
            longitudeDelta: max((lons.max()! - lons.min()!) * padding, 2)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - ActivationMapState + Camera Key

extension ActivationMapState {
    /// A hashable key for detecting camera-relevant state changes.
    var cameraKey: String {
        switch self {
        case .idle: "idle"
        case .lookupPending: "pending"
        case let .geodesicFocus(grid): "focus-\(grid)"
        }
    }
}
