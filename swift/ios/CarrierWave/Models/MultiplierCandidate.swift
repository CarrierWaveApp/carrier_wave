import CarrierWaveCore
import CoreLocation

// MARK: - MultiplierKind

/// A reason a location is flagged as a multiplier opportunity.
enum MultiplierKind: String, CaseIterable {
    /// A SOTA summit that falls inside a POTA park boundary (a POTA+SOTA 2-fer).
    case potaSota = "POTA + SOTA"
    /// A WWFF reference that shares a POTA park (a POTA+WWFF 2-fer).
    case potaWwff = "POTA + WWFF"
    /// A park/summit sitting on or near a county line (QSO-party multiplier).
    case countyLine = "County line"

    // MARK: Internal

    var systemImage: String {
        switch self {
        case .potaSota: "mountain.2.fill"
        case .potaWwff: "leaf.fill"
        case .countyLine: "map.fill"
        }
    }
}

// MARK: - MultiplierCandidate

/// A location flagged as having one or more activation multipliers, derived from
/// the overlapping boundary overlays currently loaded on the map.
struct MultiplierCandidate: Identifiable {
    let id: String
    let title: String
    let detail: String
    let latitude: Double
    let longitude: Double
    let kinds: [MultiplierKind]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// More overlapping multipliers rank higher.
    nonisolated var score: Int {
        kinds.count
    }
}

// MARK: - FfiMultiplierCandidate → MultiplierCandidate

extension MultiplierCandidate {
    /// Map an `FfiMultiplierCandidate` (the `findMultipliers` result) back to the
    /// view model, resolving each `kinds` raw value to a `MultiplierKind`. The
    /// Rust side already sorts score-desc / title-asc and preserves badge order,
    /// so the mapped array is display-ready. Returns nil if no kind resolves.
    nonisolated static func from(ffi candidate: FfiMultiplierCandidate) -> MultiplierCandidate? {
        let kinds = candidate.kinds.compactMap(MultiplierKind.init(rawValue:))
        guard !kinds.isEmpty else {
            return nil
        }
        return MultiplierCandidate(
            id: candidate.id,
            title: candidate.title,
            detail: candidate.detail,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            kinds: kinds
        )
    }
}
