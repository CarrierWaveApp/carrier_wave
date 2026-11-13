// Activation Map Helpers
//
// Utilities for map rendering in activation share cards and activation map stats.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import Foundation
import MapKit
import SwiftUI

// MARK: - ActivationMapHelpers

enum ActivationMapHelpers {
    // MARK: Internal

    /// Widest longitude span MapKit's flat map will show. Asking for more
    /// (by region or map rect) is silently clamped to this around the center.
    static let mapKitMaxLonSpan = 180.0

    /// Calculate map region from coordinates (dateline-aware)
    static func mapRegion(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> MKCoordinateRegion? {
        guard let bounds = ffiBounds(
            qsoCoordinates: qsoCoordinates,
            myCoordinate: myCoordinate
        ) else {
            return nil
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.centerLat, longitude: bounds.centerLon),
            span: MKCoordinateSpan(
                latitudeDelta: bounds.cameraLatSpan,
                longitudeDelta: bounds.cameraLonSpan
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
        guard let bounds = ffiBounds(
            qsoCoordinates: qsoCoordinates,
            myCoordinate: myCoordinate
        ) else {
            return .automatic
        }

        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.centerLat, longitude: bounds.centerLon),
            span: MKCoordinateSpan(
                latitudeDelta: bounds.cameraLatSpan,
                longitudeDelta: bounds.cameraLonSpan
            )
        ))
    }

    /// Brag-sheet framing: center horizontally on the operator QTH, then zoom
    /// in as far as possible while every contact and the great-circle arc to
    /// it still fits, plus a little padding. Keeping the QTH in the middle
    /// avoids antimeridian wraparound. The returned span may exceed
    /// ``mapKitMaxLonSpan``; check ``fitsMapKit(_:)`` before handing it to
    /// MapKit. Falls back to ``mapRegion(qsoCoordinates:myCoordinate:)`` when
    /// there is no QTH.
    static func qthCenteredRegion(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> MKCoordinateRegion? {
        guard let qth = myCoordinate else {
            return mapRegion(qsoCoordinates: qsoCoordinates, myCoordinate: nil)
        }

        // Endpoints plus arc vertices: a long great circle bows far poleward
        // of both ends, so fitting endpoints alone clips the arc.
        var points = [qth]
        for coord in qsoCoordinates {
            points.append(coord)
            points.append(contentsOf: geodesicPath(from: qth, to: coord, segments: 24))
        }

        var maxLonDelta = 0.0
        var minLat = qth.latitude
        var maxLat = qth.latitude
        for point in points {
            // Signed longitude offset from the QTH, wrapped into [-180, 180].
            let delta = remainder(point.longitude - qth.longitude, 360)
            maxLonDelta = max(maxLonDelta, abs(delta))
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
        }

        let padding = 1.2
        let lonSpan = min(max(maxLonDelta * 2 * padding, 5), 360)
        let latSpan = min(max((maxLat - minLat) * padding, 5), 170)
        let centerLat = min(max((minLat + maxLat) / 2, -80), 80)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: qth.longitude),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    /// Whether MapKit can show `region` without clamping its width.
    static func fitsMapKit(_ region: MKCoordinateRegion) -> Bool {
        region.span.longitudeDelta <= mapKitMaxLonSpan
    }

    /// True when a QTH-centered brag-sheet map is too wide for MapKit and
    /// must be drawn by the Rust flat renderer instead.
    static func needsWideRenderer(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> Bool {
        guard myCoordinate != nil,
              let region = qthCenteredRegion(qsoCoordinates: qsoCoordinates, myCoordinate: myCoordinate)
        else {
            return false
        }
        return !fitsMapKit(region)
    }

    /// ``qthCenteredRegion(qsoCoordinates:myCoordinate:)`` expanded to the
    /// image's aspect ratio for the Rust flat (equirectangular) renderer,
    /// which maps degrees linearly and so needs equal degrees per pixel.
    static func qthCenteredFlatViewport(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D,
        aspect: Double
    ) -> MKCoordinateRegion? {
        guard aspect > 0,
              let region = qthCenteredRegion(qsoCoordinates: qsoCoordinates, myCoordinate: myCoordinate)
        else {
            return nil
        }
        var lonSpan = region.span.longitudeDelta
        var latSpan = region.span.latitudeDelta
        if lonSpan / latSpan > aspect {
            latSpan = lonSpan / aspect
        } else {
            lonSpan = latSpan * aspect
        }
        lonSpan = min(lonSpan, 360)
        latSpan = min(latSpan, 170)
        // Slide the box (not the QTH column) so it stays inside ±85°.
        let half = latSpan / 2
        let centerLat = min(max(region.center.latitude, -85 + half), 85 - half)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: myCoordinate.longitude),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    /// Whether the given coordinates require a globe-level view
    static func requiresGlobeView(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> Bool {
        guard let bounds = ffiBounds(
            qsoCoordinates: qsoCoordinates,
            myCoordinate: myCoordinate
        ) else {
            return false
        }
        return bounds.requiresGlobeView
    }

    /// Generate a geodesic (great circle) path between two coordinates.
    /// Returns a single path — use ``geodesicSegments(from:to:segments:)``
    /// when the path may cross the antimeridian.
    static func geodesicPath(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        segments: Int = 50
    ) -> [CLLocationCoordinate2D] {
        geodesicSegments(from: start, to: end, segments: segments)
            .flatMap { $0 }
    }

    /// Generate geodesic path segments split at antimeridian crossings.
    /// Each inner array is a continuous segment that does not cross ±180°.
    static func geodesicSegments(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        segments: Int = 50
    ) -> [[CLLocationCoordinate2D]] {
        greatCircleArc(
            from: FfiCoordinate(latitude: start.latitude, longitude: start.longitude),
            to: FfiCoordinate(latitude: end.latitude, longitude: end.longitude),
            segments: UInt32(segments)
        ).map { polyline in
            polyline.points.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        }
    }

    /// Compute the tightest enclosing longitude bounds for a set of
    /// longitudes, accounting for antimeridian wrap.
    ///
    /// Returns `(minLon, maxLon)` where `maxLon - minLon` is the minimal
    /// angular span containing every input. The returned values may be
    /// outside `[-180, 180]` when the minimal enclosing arc wraps the
    /// antimeridian (e.g. `(170, 370)` for points at 170°, -179°, -120°).
    /// Callers passing the center to `MKCoordinateRegion` should normalize
    /// it back into `[-180, 180]` via modular arithmetic.
    ///
    /// The algorithm finds the largest "empty" gap between consecutive
    /// sorted longitudes (including the wrap gap from last to first+360).
    /// The complementary arc is the minimal enclosing span.
    static func tightestLongitudeBounds(
        _ longitudes: [Double]
    ) -> (minLon: Double, maxLon: Double)? {
        guard let firstLon = longitudes.first else {
            return nil
        }
        let sorted = longitudes.sorted()
        guard sorted.count > 1 else {
            return (firstLon, firstLon)
        }

        var maxInteriorGap = 0.0
        var gapEndIndex = 0
        for idx in 1 ..< sorted.count {
            let gap = sorted[idx] - sorted[idx - 1]
            if gap > maxInteriorGap {
                maxInteriorGap = gap
                gapEndIndex = idx
            }
        }

        // The wrap-around gap from last back to first+360.
        let wrapGap = (sorted[0] + 360) - sorted[sorted.count - 1]
        if wrapGap >= maxInteriorGap {
            // Wrap is the biggest empty arc — no shifting needed.
            return (sorted[0], sorted[sorted.count - 1])
        }

        // Interior gap is biggest. Shift points before the gap by +360 so
        // they become contiguous with points after the gap.
        let shiftedMin = sorted[gapEndIndex]
        let shiftedMax = sorted[gapEndIndex - 1] + 360
        return (shiftedMin, shiftedMax)
    }

    // MARK: Private

    // MARK: - Coordinate Bounds (dateline-aware, via FFI)

    private static func ffiBounds(
        qsoCoordinates: [CLLocationCoordinate2D],
        myCoordinate: CLLocationCoordinate2D?
    ) -> FfiMapBounds? {
        var allCoordinates = qsoCoordinates
        if let myCoord = myCoordinate {
            allCoordinates.append(myCoord)
        }
        guard !allCoordinates.isEmpty else {
            return nil
        }
        return mapBoundsFor(coords: allCoordinates.map {
            FfiCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        })
    }
}

// MARK: - ActivationStatsHelper

/// Computes distance/rate statistics for a POTA activation's QSOs
enum ActivationStatsHelper {
    static func statistics(for activation: POTAActivation) -> MapStatistics {
        statistics(forQSOs: activation.qsos)
    }

    /// Same statistics as the activation overload, just keyed off the QSO list
    /// so callers without a `POTAActivation` (e.g. SOTA-only sessions sharing
    /// through the unified brag card) can compute distance/rate metrics too.
    static func statistics(forQSOs qsos: [QSO]) -> MapStatistics {
        let rows: [FfiMapStatInput] = qsos.map { qso in
            FfiMapStatInput(
                myGrid: qso.myGrid,
                theirGrid: qso.theirGrid,
                qsoDate: Int64(qso.timestamp.timeIntervalSince1970),
                power: qso.power.map(Int64.init),
                loggingSessionId: qso.loggingSessionId?.uuidString,
                state: qso.state,
                dxcc: qso.dxcc.map(Int64.init)
            )
        }
        return QSOMapView.statistics(from: computeMapStatistics(rows: rows))
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
