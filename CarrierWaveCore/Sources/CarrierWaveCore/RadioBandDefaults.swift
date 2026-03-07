//
//  RadioBandDefaults.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - RadioBandDefaults

/// Default frequencies for each amateur band by mode
enum RadioBandDefaults {
    struct BandDefault {
        let cw: Double
        let ssb: Double
        let ft8: Double
        let ft4: Double?
    }

    static let table: [String: BandDefault] = [
        "160M": BandDefault(cw: 1.810, ssb: 1.900, ft8: 1.840, ft4: 1.840),
        "80M": BandDefault(cw: 3.530, ssb: 3.800, ft8: 3.573, ft4: 3.575),
        "60M": BandDefault(cw: 5.332, ssb: 5.332, ft8: 5.357, ft4: nil),
        "40M": BandDefault(cw: 7.030, ssb: 7.200, ft8: 7.074, ft4: 7.047),
        "30M": BandDefault(cw: 10.110, ssb: 10.110, ft8: 10.136, ft4: 10.140),
        "20M": BandDefault(cw: 14.030, ssb: 14.250, ft8: 14.074, ft4: 14.080),
        "17M": BandDefault(cw: 18.080, ssb: 18.130, ft8: 18.100, ft4: 18.104),
        "15M": BandDefault(cw: 21.030, ssb: 21.300, ft8: 21.074, ft4: 21.140),
        "12M": BandDefault(cw: 24.900, ssb: 24.950, ft8: 24.915, ft4: 24.919),
        "10M": BandDefault(cw: 28.030, ssb: 28.500, ft8: 28.074, ft4: 28.180),
        "6M": BandDefault(cw: 50.090, ssb: 50.150, ft8: 50.313, ft4: 50.318),
        "2M": BandDefault(cw: 144.050, ssb: 144.200, ft8: 144.174, ft4: 144.170),
    ]

    /// Resolve a band shortcut (e.g. "20M") to a frequency for the given mode
    static func resolve(_ token: String, currentMode: String?) -> Double? {
        guard let defaults = table[token] else {
            return nil
        }
        let mode = currentMode?.uppercased() ?? "CW"
        return switch mode {
        case "FT8": defaults.ft8
        case "FT4": defaults.ft4 ?? defaults.ft8
        case "SSB",
             "USB",
             "LSB",
             "AM",
             "FM": defaults.ssb
        default: defaults.cw
        }
    }
}
