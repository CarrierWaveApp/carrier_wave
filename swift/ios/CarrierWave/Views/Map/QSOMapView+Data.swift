import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - QSOMapView FFI Data Layer

//
// All filtering/clustering/stats/arc math lives in Rust (MapApi.qso_map).
// This file only translates FFI records into the UI model types.

extension QSOMapView {
    /// Build the FFI filter from current filter state.
    static func ffiFilter(from state: MapFilterState) -> FfiMapFilter {
        FfiMapFilter(
            band: state.selectedBand,
            mode: state.selectedMode,
            park: state.selectedPark,
            startDate: state.startDate.map { Int64($0.timeIntervalSince1970) },
            endDate: state.endDate.map { Int64($0.timeIntervalSince1970) },
            confirmedOnly: state.confirmedOnly,
            showIndividual: state.showIndividualQSOs,
            showPaths: state.showPaths,
            maxQsos: state.showAllQSOs ? nil : UInt32(MapFilterState.maxQSOsDefault)
        )
    }

    static func annotation(from ffi: FfiQsoMapAnnotation) -> QSOAnnotation {
        QSOAnnotation(
            id: ffi.id,
            coordinate: CLLocationCoordinate2D(latitude: ffi.latitude, longitude: ffi.longitude),
            gridSquare: ffi.gridSquare,
            qsoCount: Int(ffi.qsoCount),
            callsigns: ffi.callsigns,
            mostRecentDate: Date(timeIntervalSince1970: TimeInterval(ffi.mostRecent)),
            parkReferences: Set(ffi.parkReferences),
            weather: ffi.weather,
            solarConditions: ffi.solarConditions,
            averageWPM: ffi.averageWpm.map(Int.init),
            radio: ffi.radio,
            antenna: ffi.antenna,
            key: ffi.key,
            mic: ffi.mic
        )
    }

    static func arc(from ffi: FfiMapArc) -> QSOArc {
        QSOArc(
            id: ffi.id,
            callsign: ffi.callsign,
            path: ffi.segments.flatMap { segment in
                segment.points.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            }
        )
    }

    static func statistics(from ffi: FfiMapStats) -> MapStatistics {
        MapStatistics(
            activationDuration: ffi.durationSeconds.map(TimeInterval.init),
            qsoRate: ffi.qsoRate,
            averageDistanceKm: ffi.averageDistanceKm,
            longestDistanceKm: ffi.longestDistanceKm,
            wattsPerMile: ffi.wattsPerMile
        )
    }
}

// MARK: - MapStatistics

/// Computed distance and rate statistics (rendered by MapStatsOverlay).
nonisolated struct MapStatistics {
    static let empty = MapStatistics(
        activationDuration: nil, qsoRate: nil, averageDistanceKm: nil,
        longestDistanceKm: nil, wattsPerMile: nil
    )

    let activationDuration: TimeInterval?
    let qsoRate: Double?
    let averageDistanceKm: Double?
    let longestDistanceKm: Double?
    let wattsPerMile: Double?
}
