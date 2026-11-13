//
//  AntennaType+DisplayName.swift
//  CarrierWave
//

import CarrierWaveCore

extension AntennaType {
    var displayName: String {
        switch self {
        case .dipole: "Dipole"
        case .vertical: "Vertical"
        case .loop: "Mag Loop"
        case .yagi: "Yagi"
        case .logPeriodic: "Log Periodic"
        case .whip: "Whip"
        case .beverage: "Beverage"
        case .longwire: "Long Wire"
        case .endFed: "EFHW"
        case .hexBeam: "Hex Beam"
        case .unknown: "Unknown"
        }
    }
}
