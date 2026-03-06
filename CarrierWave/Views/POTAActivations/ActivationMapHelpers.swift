// Activation Map Helpers
//
// Utilities for map rendering in activation share cards and activation map stats.

import CarrierWaveData
import Foundation
import MapKit
import SwiftUI

// MARK: - ActivationMapHelpers

enum ActivationMapHelpers {
    // MARK: Internal

    /// Calculate map region from coordinates (dateline-aware)
    static func mapRegion(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> MKCoordinateRegion? {
        guard let bounds = coordinateBounds(
            qsoCoordinates: qsoCoordinates,
            myCoordinate: myCoordinate
        ) else {
            return nil
        }

        let latSpan = min(max(bounds.latSpan, 5) * 1.3, 180)
        let lonSpan = min(max(bounds.lonSpan, 5) * 1.3, 360)

        return MKCoordinateRegion(
            center: bounds.center,
            span: MKCoordinateSpan(
                latitudeDelta: latSpan,
                longitudeDelta: lonSpan
            )
        )
    }

    /// Returns a camera position with dateline-aware centering.
    /// Pads large spans generously so all endpoints are visible.
    /// Note: Globe rendering is not available on physical iPhones (MapKit limitation).
    static func mapCameraPosition(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> MapCameraPosition {
        guard let bounds = coordinateBounds(
            qsoCoordinates: qsoCoordinates,
            myCoordinate: myCoordinate
        ) else {
            return .automatic
        }

        // Extra padding for large spans so endpoints aren't clipped
        let padding: Double = bounds.lonSpan > globeThreshold ? 1.5 : 1.3
        let latSpan = min(max(bounds.latSpan, 5) * padding, 180)
        let lonSpan = min(max(bounds.lonSpan, 5) * padding, 360)

        return .region(MKCoordinateRegion(
            center: bounds.center,
            span: MKCoordinateSpan(
                latitudeDelta: latSpan,
                longitudeDelta: lonSpan
            )
        ))
    }

    /// Whether the given coordinates require a globe-level view
    static func requiresGlobeView(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> Bool {
        guard let bounds = coordinateBounds(
            qsoCoordinates: qsoCoordinates,
            myCoordinate: myCoordinate
        ) else {
            return false
        }
        return max(bounds.latSpan, bounds.lonSpan) > globeThreshold
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

    // MARK: Private

    // MARK: - Coordinate Bounds (dateline-aware)

    private struct CoordinateBounds {
        let center: CLLocationCoordinate2D
        let latSpan: Double
        let lonSpan: Double
    }

    /// Threshold in degrees: spans larger than this use a globe camera
    private static let globeThreshold: Double = 90

    private static func coordinateBounds(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> CoordinateBounds? {
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

        let latSpan = maxLat - minLat
        let centerLat = (minLat + maxLat) / 2

        // Check if crossing the dateline produces a shorter longitude span
        let directLonSpan = maxLon - minLon
        let datelineLonSpan = 360 - directLonSpan

        let centerLon: Double
        let lonSpan: Double

        if datelineLonSpan < directLonSpan {
            // Shorter to go across the dateline
            lonSpan = datelineLonSpan
            let rawCenter = maxLon + datelineLonSpan / 2
            centerLon = rawCenter > 180 ? rawCenter - 360 : rawCenter
        } else {
            lonSpan = directLonSpan
            centerLon = (minLon + maxLon) / 2
        }

        return CoordinateBounds(
            center: CLLocationCoordinate2D(
                latitude: centerLat,
                longitude: centerLon
            ),
            latSpan: latSpan,
            lonSpan: lonSpan
        )
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
