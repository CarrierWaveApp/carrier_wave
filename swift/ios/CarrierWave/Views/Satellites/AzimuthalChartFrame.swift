import CoreLocation
import SwiftUI

// MARK: - AzimuthalChartFrame

/// Azimuthal-equidistant projection centered on the observer: bearing from
/// the observer is the screen angle, great-circle distance is the radius.
/// The device compass heading is folded straight into the screen angle, so
/// the whole chart rotates freely at any scale (unlike MKMapView, which
/// force-locks north-up when zoomed out).
nonisolated struct AzimuthalChartFrame {
    // MARK: Lifecycle

    init(size: CGSize, observer: CLLocationCoordinate2D, headingDeg: Double, zoom: CGFloat) {
        screenCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        let baseRadius = max(1, min(size.width, size.height) / 2 - 18)
        diskRadius = baseRadius * zoom
        // The projection center (home point) always renders at the screen
        // center; panning changes WHICH coordinate that is, not where it is.
        center = screenCenter
        // Compass letters stick to the rim until it leaves the screen,
        // then pin to the screen edge so orientation survives zooming.
        compassRadius = min(diskRadius + 11, baseRadius + 7)
        self.zoom = zoom
        observerLatRad = observer.latitude * .pi / 180
        observerLonRad = observer.longitude * .pi / 180
        headingRad = headingDeg * .pi / 180
    }

    // MARK: Internal

    /// Half the Earth's circumference — the antipode lands on the rim.
    static let maxDistanceKm = Double.pi * 6_371.0

    let center: CGPoint
    let screenCenter: CGPoint
    let diskRadius: CGFloat
    let compassRadius: CGFloat
    let zoom: CGFloat
    let headingRad: Double

    /// Inverse projection: the lat/lon under a screen point, used to commit
    /// a drag as a new projection center.
    func coordinate(at point: CGPoint) -> CLLocationCoordinate2D {
        let deltaX = Double(point.x - center.x)
        let deltaY = Double(point.y - center.y)
        let radius = hypot(deltaX, deltaY)
        guard radius > 0.5 else {
            return CLLocationCoordinate2D(
                latitude: observerLatRad * 180 / .pi,
                longitude: observerLonRad * 180 / .pi
            )
        }
        let bearing = atan2(deltaX, -deltaY) + headingRad
        let angular = min(radius / Double(diskRadius) * .pi, .pi * 0.999)
        let lat = asin(
            sin(observerLatRad) * cos(angular) + cos(observerLatRad) * sin(angular) * cos(bearing)
        )
        let lon = observerLonRad + atan2(
            sin(bearing) * sin(angular) * cos(observerLatRad),
            cos(angular) - sin(observerLatRad) * sin(lat)
        )
        var lonDeg = lon * 180 / .pi
        if lonDeg > 180 {
            lonDeg -= 360
        }
        if lonDeg < -180 {
            lonDeg += 360
        }
        return CLLocationCoordinate2D(latitude: lat * 180 / .pi, longitude: lonDeg)
    }

    /// Compass letters anchor to the screen center.
    func compassPoint(bearingDeg: Double) -> CGPoint {
        let angle = bearingDeg * .pi / 180 - headingRad
        return CGPoint(
            x: screenCenter.x + compassRadius * CGFloat(sin(angle)),
            y: screenCenter.y - compassRadius * CGFloat(cos(angle))
        )
    }

    /// Angular distance (radians) from the observer to a point.
    func angularDistance(latDeg: Double, lonDeg: Double) -> Double {
        let lat = latDeg * .pi / 180
        let lonDelta = lonDeg * .pi / 180 - observerLonRad
        let cosine = sin(observerLatRad) * sin(lat)
            + cos(observerLatRad) * cos(lat) * cos(lonDelta)
        return acos(max(-1, min(1, cosine)))
    }

    /// Screen position of a lat/lon under the current rotation.
    func point(latDeg: Double, lonDeg: Double) -> CGPoint {
        let lat = latDeg * .pi / 180
        let lonDelta = lonDeg * .pi / 180 - observerLonRad
        let bearing = atan2(
            sin(lonDelta) * cos(lat),
            cos(observerLatRad) * sin(lat) - sin(observerLatRad) * cos(lat) * cos(lonDelta)
        )
        let radius = CGFloat(angularDistance(latDeg: latDeg, lonDeg: lonDeg) / .pi) * diskRadius
        let angle = bearing - headingRad
        return CGPoint(
            x: center.x + radius * CGFloat(sin(angle)),
            y: center.y - radius * CGFloat(cos(angle))
        )
    }

    /// Screen position at a given distance ring and compass bearing.
    func ringPoint(bearingDeg: Double, radius: CGFloat) -> CGPoint {
        let angle = bearingDeg * .pi / 180 - headingRad
        return CGPoint(
            x: center.x + radius * CGFloat(sin(angle)),
            y: center.y - radius * CGFloat(cos(angle))
        )
    }

    // MARK: Private

    private let observerLatRad: Double
    private let observerLonRad: Double
}
