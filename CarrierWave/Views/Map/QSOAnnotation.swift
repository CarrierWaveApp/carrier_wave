import CoreLocation
import Foundation

// MARK: - QSOAnnotation

/// Represents a cluster of QSOs at a location for map display
struct QSOAnnotation: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let gridSquare: String
    let qsoCount: Int
    let callsigns: [String]
    let mostRecentDate: Date
    /// Park references associated with QSOs in this cluster
    let parkReferences: Set<String>
    /// Activation weather conditions (from ActivationMetadata)
    let weather: String?
    /// Activation solar conditions (from ActivationMetadata)
    let solarConditions: String?
    /// Average CW speed from RBN spots (from ActivationMetadata)
    let averageWPM: Int?
    /// Radio used (from QSO myRig)
    let radio: String?
    /// Antenna used (from LoggingSession)
    let antenna: String?
    /// CW key used (from LoggingSession)
    let key: String?
    /// Microphone used (from LoggingSession)
    let mic: String?

    /// Display title showing grid and count
    var displayTitle: String {
        if qsoCount == 1, let callsign = callsigns.first {
            return callsign
        }
        return "\(gridSquare) (\(qsoCount))"
    }

    /// Subtitle showing sample callsigns
    var displaySubtitle: String? {
        if qsoCount == 1 {
            return gridSquare
        }
        let sample = callsigns.prefix(3).joined(separator: ", ")
        if qsoCount > 3 {
            return "\(sample), +\(qsoCount - 3) more"
        }
        return sample
    }

    // MARK: Hashable

    static func == (lhs: QSOAnnotation, rhs: QSOAnnotation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - QSOArc

/// Represents an arc between user location and a contact.
/// The geodesic path is pre-computed at creation time so the view body
/// never performs trig during render.
struct QSOArc: Identifiable {
    // MARK: Lifecycle

    /// Create an arc, pre-computing the geodesic path.
    /// - Parameter segments: Number of segments (more = smoother curve)
    init(id: String, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
         callsign: String, segments: Int = 30)
    {
        self.id = id
        self.from = from
        self.to = to
        self.callsign = callsign
        path = Self.computeGeodesicPath(from: from, to: to, segments: segments)
    }

    // MARK: Internal

    let id: String
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let callsign: String
    /// Pre-computed geodesic path coordinates
    let path: [CLLocationCoordinate2D]

    // MARK: Private

    /// Calculate intermediate points along the great circle path
    private static func computeGeodesicPath(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        segments: Int
    ) -> [CLLocationCoordinate2D] {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180

        // Angular distance between points
        let angularDist =
            2
                * asin(
                    sqrt(
                        pow(sin((lat1 - lat2) / 2), 2) + cos(lat1) * cos(lat2)
                            * pow(sin((lon1 - lon2) / 2), 2)
                    )
                )

        // Skip if points are too close
        guard angularDist > 0.001 else {
            return [from, to]
        }

        var points: [CLLocationCoordinate2D] = []
        points.reserveCapacity(segments + 1)

        for i in 0 ... segments {
            let fraction = Double(i) / Double(segments)

            let coeffA = sin((1 - fraction) * angularDist) / sin(angularDist)
            let coeffB = sin(fraction * angularDist) / sin(angularDist)

            let x = coeffA * cos(lat1) * cos(lon1) + coeffB * cos(lat2) * cos(lon2)
            let y = coeffA * cos(lat1) * sin(lon1) + coeffB * cos(lat2) * sin(lon2)
            let z = coeffA * sin(lat1) + coeffB * sin(lat2)

            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi

            points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return points
    }
}
