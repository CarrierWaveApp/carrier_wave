import CoreLocation
import UIKit

// MARK: - ProgramAvailability

/// Ranks activity programs (POTA, SOTA, WWFF) by how much nearby
/// activity exists around the operator's home coordinate. Used by the
/// Sessions intent view to stop advertising "POTA" first to a user in
/// the UK where WWFF has thousands of references and POTA has a few
/// dozen.
///
/// The ranking is a *display* helper only — actual program selection
/// still happens via the Activate flow where the user can pick any
/// program regardless of nearby counts.
enum ProgramAvailability {
    /// Program short codes (lowercase, stable across UI).
    enum Program: String, CaseIterable {
        case pota
        case sota
        case wwff
        case aoa

        // MARK: Internal

        var displayName: String {
            switch self {
            case .pota: "POTA"
            case .sota: "SOTA"
            case .wwff: "WWFF"
            case .aoa: "AoA"
            }
        }
    }

    /// Returns program codes ordered by descending nearby-activity count.
    /// Programs with zero nearby entries are moved to the back but not
    /// removed (so the user still sees them as options). AoA has no
    /// geographic reference data and is always last.
    ///
    /// Reads from the three reference caches synchronously — callers
    /// should invoke this on the main thread after the caches have
    /// loaded (they are preloaded during app startup).
    static func orderedPrograms(
        near coordinate: CLLocationCoordinate2D? = nil,
        radiusKm: Double = 300
    ) -> [Program] {
        guard let coord = coordinate ?? DeviceLocationHint.bestKnownHomeCoordinate else {
            return Program.allCases
        }
        let potaCount = POTAParksCache.shared.nearbyParks(
            latitude: coord.latitude,
            longitude: coord.longitude,
            limit: 50,
            maxDistanceKm: radiusKm
        ).count
        let sotaCount = SOTASummitsCache.shared.nearbySummits(
            latitude: coord.latitude,
            longitude: coord.longitude,
            limit: 50,
            maxDistanceKm: radiusKm
        ).count
        let wwffCount = WWFFReferencesCache.shared.nearbyReferences(
            latitude: coord.latitude,
            longitude: coord.longitude,
            limit: 50,
            maxDistanceKm: radiusKm
        ).count

        let ranked: [(Program, Int)] = [
            (.pota, potaCount),
            (.sota, sotaCount),
            (.wwff, wwffCount),
        ].sorted { $0.1 > $1.1 }

        return ranked.map(\.0) + [.aoa]
    }

    /// Comma-separated subtitle for the Activate intent card — e.g.
    /// "WWFF, POTA, SOTA, AoA" — based on nearby availability.
    static func activateSubtitle() -> String {
        orderedPrograms()
            .map(\.displayName)
            .joined(separator: ", ")
    }
}
