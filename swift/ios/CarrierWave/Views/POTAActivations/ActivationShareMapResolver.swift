// Activation Share Map Resolver
//
// Resolves a coordinate for every contact on the activation share card at
// presentation time, from the current QSO records. A QSO with no grid is
// not dropped outright — it falls through their park → their summit → DXCC
// entity centroid before being counted as "without location", so a session
// logged offline (callsign lookups never ran) still produces a map.
//
// Everything here is `nonisolated` so the chain runs off the main actor;
// the only main-actor step is snapshotting the SwiftData QSO into a
// value-typed `ActivationShareContact`.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import UIKit

// MARK: - ActivationShareContact

/// The value-typed slice of a QSO the map needs. Extracted on the main actor
/// so the resolver can run off-main without touching SwiftData objects.
nonisolated struct ActivationShareContact: Sendable {
    // MARK: Lifecycle

    init(
        callsign: String,
        theirGrid: String? = nil,
        theirParkReference: String? = nil,
        sotaRef: String? = nil,
        rstColor: UIColor = .white
    ) {
        self.callsign = callsign
        self.theirGrid = theirGrid
        self.theirParkReference = theirParkReference
        self.sotaRef = sotaRef
        self.rstColor = rstColor
    }

    @MainActor
    init(qso: QSO) {
        self.init(
            callsign: qso.callsign,
            theirGrid: qso.theirGrid,
            theirParkReference: qso.theirParkReference,
            sotaRef: qso.sotaRef,
            rstColor: RSTColorHelper.uiColor(
                rstSent: qso.rstSent, rstReceived: qso.rstReceived
            )
        )
    }

    // MARK: Internal

    let callsign: String
    let theirGrid: String?
    let theirParkReference: String?
    let sotaRef: String?
    let rstColor: UIColor
}

// MARK: - ActivationShareMapMarkers

/// Resolver output: everything we could place, plus how many we couldn't.
nonisolated struct ActivationShareMapMarkers: Sendable {
    let markers: [ShareMapMarker]
    let withoutLocationCount: Int

    /// Caption for the share card map, e.g. "3 contacts without location".
    /// `nil` when every contact was placed.
    var withoutLocationCaption: String? {
        Self.caption(forCount: withoutLocationCount)
    }

    static func caption(forCount count: Int) -> String? {
        guard count > 0 else {
            return nil
        }
        return count == 1
            ? "1 contact without location"
            : "\(count) contacts without location"
    }
}

// MARK: - ActivationShareMapResolver

nonisolated enum ActivationShareMapResolver {
    // MARK: Internal

    /// Coordinate sources for the fallback chain. Injected so tests can run
    /// the chain without the park/summit caches.
    struct Lookups: Sendable {
        /// Production lookups: POTA park cache, SOTA summit cache, and the
        /// DXCC prefix table's representative coordinate for the callsign.
        static let live = Lookups(
            parkCoordinate: { reference in
                guard let park = POTAParksCache.shared.parkSync(for: reference) else {
                    return nil
                }
                if let lat = park.latitude, let lon = park.longitude {
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                return park.grid.flatMap(MaidenheadConverter.coordinate(from:))
            },
            summitCoordinate: { code in
                guard let summit = SOTASummitsCache.shared.lookupSummit(code) else {
                    return nil
                }
                if let lat = summit.latitude, let lon = summit.longitude {
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                return summit.grid.flatMap(MaidenheadConverter.coordinate(from:))
            },
            entityCoordinate: { callsign in
                guard let entity = LocationPrefixLookup.entity(forCallsign: callsign) else {
                    return nil
                }
                return CLLocationCoordinate2D(
                    latitude: entity.latitude, longitude: entity.longitude
                )
            }
        )

        /// No fallbacks at all — grid only.
        static let none = Lookups(
            parkCoordinate: { _ in nil },
            summitCoordinate: { _ in nil },
            entityCoordinate: { _ in nil }
        )

        let parkCoordinate: @Sendable (String) -> CLLocationCoordinate2D?
        let summitCoordinate: @Sendable (String) -> CLLocationCoordinate2D?
        let entityCoordinate: @Sendable (String) -> CLLocationCoordinate2D?
    }

    /// Resolve every contact through the chain
    /// grid → their park → their summit → DXCC centroid → skip.
    static func resolve(
        contacts: [ActivationShareContact],
        lookups: Lookups
    ) -> ActivationShareMapMarkers {
        var markers: [ShareMapMarker] = []
        var missing = 0
        for contact in contacts {
            guard let coordinate = coordinate(for: contact, lookups: lookups) else {
                missing += 1
                continue
            }
            markers.append(ShareMapMarker(coordinate: coordinate, rstColor: contact.rstColor))
        }
        return ActivationShareMapMarkers(markers: markers, withoutLocationCount: missing)
    }

    /// Single-contact chain. Exposed for tests.
    static func coordinate(
        for contact: ActivationShareContact,
        lookups: Lookups
    ) -> CLLocationCoordinate2D? {
        if let grid = contact.theirGrid, grid.count >= 4,
           let coordinate = MaidenheadConverter.coordinate(from: grid)
        {
            return coordinate
        }
        // Multi-park (two-fer) references are stored comma-separated; the
        // first park that resolves is representative enough for a pin.
        for reference in references(contact.theirParkReference) {
            if let coordinate = lookups.parkCoordinate(reference) {
                return coordinate
            }
        }
        for reference in references(contact.sotaRef) {
            if let coordinate = lookups.summitCoordinate(reference) {
                return coordinate
            }
        }
        let callsign = contact.callsign.trimmingCharacters(in: .whitespaces)
        guard !callsign.isEmpty else {
            return nil
        }
        return lookups.entityCoordinate(callsign)
    }

    // MARK: Private

    private static func references(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else {
            return []
        }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }
}
