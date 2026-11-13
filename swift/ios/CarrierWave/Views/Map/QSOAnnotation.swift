import CarrierWaveData
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
/// The geodesic path is pre-computed by Rust (`greatCircleArc`) so the
/// view body never performs trig during render.
nonisolated struct QSOArc: Identifiable {
    let id: String
    let callsign: String
    /// Pre-computed geodesic path from Rust (antimeridian-split, flattened).
    let path: [CLLocationCoordinate2D]
}
