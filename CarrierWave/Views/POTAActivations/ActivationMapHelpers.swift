// Activation Map Helpers
//
// Utilities for map rendering in activation share cards and activation map stats.

import Foundation
import MapKit

// MARK: - ActivationMapHelpers

enum ActivationMapHelpers {
    /// Calculate map region from coordinates
    static func mapRegion(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> MKCoordinateRegion? {
        var allCoordinates = qsoCoordinates
        if let myCoord = myCoordinate {
            allCoordinates.append(myCoord)
        }

        guard !allCoordinates.isEmpty else {
            return nil
        }

        let lats = allCoordinates.map(\.latitude)
        let lons = allCoordinates.map(\.longitude)

        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max()
        else {
            return nil
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let latSpan = min(max(maxLat - minLat, 5) * 1.3, 180)
        let lonSpan = min(max(maxLon - minLon, 5) * 1.3, 360)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    /// Generate a geodesic (great circle) path between two coordinates
    static func geodesicPath(
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

        guard angularDistance > 0 else {
            return [start, end]
        }

        for i in 0 ... segments {
            let fraction = Double(i) / Double(segments)
            let coeffA = sin((1 - fraction) * angularDistance) / sin(angularDistance)
            let coeffB = sin(fraction * angularDistance) / sin(angularDistance)

            let x = coeffA * cos(lat1) * cos(lon1) + coeffB * cos(lat2) * cos(lon2)
            let y = coeffA * cos(lat1) * sin(lon1) + coeffB * cos(lat2) * sin(lon2)
            let z = coeffA * sin(lat1) + coeffB * sin(lat2)

            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi

            path.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return path
    }
}

// MARK: - ActivationStatsHelper

/// Computes distance/rate statistics for a POTA activation's QSOs
enum ActivationStatsHelper {
    static func statistics(for activation: POTAActivation) -> MapStatistics {
        let snapshots: [MapQSOSnapshot] = activation.qsos.map { qso in
            MapQSOSnapshot(
                id: qso.id,
                callsign: qso.callsign,
                band: qso.band,
                mode: qso.mode,
                timestamp: qso.timestamp,
                myGrid: qso.myGrid,
                theirGrid: qso.theirGrid,
                parkReference: qso.parkReference,
                state: qso.state,
                dxccNumber: qso.dxcc,
                lotwConfirmed: qso.lotwConfirmed,
                qrzConfirmed: qso.qrzConfirmed,
                power: qso.power,
                loggingSessionId: qso.loggingSessionId,
                myRig: qso.myRig
            )
        }
        return QSOMapView.computeStatistics(from: snapshots)
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }

    static func formatDistance(_ km: Double) -> String {
        UnitFormatter.distance(km)
    }
}
