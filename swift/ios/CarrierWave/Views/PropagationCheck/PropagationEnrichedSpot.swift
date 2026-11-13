import CarrierWaveCwFfi
import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - PropagationEnrichedSpot

/// A propagation spot augmented with derived geographic data — effective grid
/// (after the enrichment waterfall), `CLLocationCoordinate2D`, distance, and
/// bearing from the operator's grid. The projection runs in the Rust
/// `PropagationApi` now; this is the host-side view model the map, spots list,
/// and azimuthal card share.
struct PropagationEnrichedSpot: Identifiable {
    let id: String
    let entry: PropagationSpotEntry
    let effectiveGrid: String?
    let coordinate: CLLocationCoordinate2D?
    let distanceKm: Double?
    let bearing: Double?
}

// MARK: - FFI bridging

extension PropagationSpotEntry {
    /// Map a Rust `FfiPropagationSpot` into the host spot model. Lat/lon are not
    /// carried on the FFI spot (they live on the enriched projection); the host
    /// model keeps them nil here.
    init(ffi: FfiPropagationSpot) {
        self.init(
            source: PropagationSpotSource(rawValue: ffi.source) ?? .rbn,
            skimmerCall: ffi.skimmerCall,
            skimmerGrid: ffi.skimmerGrid,
            skimmerLat: nil,
            skimmerLon: nil,
            freqHz: Int(ffi.freqHz),
            band: ffi.band,
            mode: ffi.mode,
            snrDB: ffi.snrDb,
            timestamp: Date(timeIntervalSince1970: ffi.timestampEpoch)
        )
    }
}

extension PropagationEnrichedSpot {
    /// Map a Rust `FfiPropagationEnrichedSpot` into the host view model.
    init(ffi: FfiPropagationEnrichedSpot) {
        var coordinate: CLLocationCoordinate2D?
        if let latitude = ffi.latitude, let longitude = ffi.longitude {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        self.init(
            id: ffi.id,
            entry: PropagationSpotEntry(ffi: ffi.spot),
            effectiveGrid: ffi.effectiveGrid,
            coordinate: coordinate,
            distanceKm: ffi.distanceKm,
            bearing: ffi.bearing
        )
    }
}

extension PropagationConnectivityGap {
    /// Map a Rust `FfiPropagationConnectivityGap` into the persisted host gap.
    init(ffi: FfiPropagationConnectivityGap) {
        self.init(
            source: PropagationSpotSource(rawValue: ffi.source) ?? .rbn,
            startedAt: Date(timeIntervalSince1970: ffi.startedAtEpoch),
            endedAt: Date(timeIntervalSince1970: ffi.endedAtEpoch)
        )
    }
}

extension PropagationStopReason {
    /// Map the persisted host stop reason onto the FFI enum for `stop(reason:)`.
    var ffiStopReason: FfiPropagationStopReason {
        switch self {
        case .user: .user
        case .duration: .duration
        case .radioFault: .radioFault
        }
    }

    /// Map a Rust `FfiPropagationStopReason` back into the host enum.
    init(ffi: FfiPropagationStopReason) {
        switch ffi {
        case .user: self = .user
        case .duration: self = .duration
        case .radioFault: self = .radioFault
        }
    }
}
