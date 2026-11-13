//
//  DistanceOption.swift
//  CarrierWave
//

import CarrierWaveCore

// MARK: - DistanceOption

enum DistanceOption: CaseIterable {
    case regional // 2,500 km
    case continental // 5,000 km
    case hemispheric // 10,000 km
    case global // 20,000 km

    // MARK: Internal

    var km: Double {
        switch self {
        case .regional: 2_500
        case .continental: 5_000
        case .hemispheric: 10_000
        case .global: AzimuthalProjection.earthHalfCircumferenceKm
        }
    }

    var label: String {
        switch self {
        case .regional: "Regional (2,500 km)"
        case .continental: "Continental (5,000 km)"
        case .hemispheric: "Hemispheric (10,000 km)"
        case .global: "Global"
        }
    }

    var shortLabel: String {
        switch self {
        case .regional: "2.5k km"
        case .continental: "5k km"
        case .hemispheric: "10k km"
        case .global: "Global"
        }
    }
}
