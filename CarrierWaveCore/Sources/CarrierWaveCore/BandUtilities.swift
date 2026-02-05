//
//  BandUtilities.swift
//  CarrierWaveCore
//

import Foundation

/// Utility for band-related operations
public enum BandUtilities: Sendable {
    /// Band order for sorting (frequency order low to high)
    public static let bandOrder = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m",
        "70cm", "Other",
    ]

    /// Derives the amateur radio band from a frequency in kHz
    /// - Parameter frequencyKHz: Frequency in kilohertz
    /// - Returns: Band designation (e.g., "20m") or nil if not a recognized band
    public static func deriveBand(from frequencyKHz: Double?) -> String? {
        guard let kHz = frequencyKHz else {
            return nil
        }
        let mhz = kHz / 1_000.0

        switch mhz {
        case 1.8 ..< 2.0: return "160m"
        case 3.5 ..< 4.0: return "80m"
        case 5.3 ..< 5.4: return "60m"
        case 7.0 ..< 7.3: return "40m"
        case 10.1 ..< 10.15: return "30m"
        case 14.0 ..< 14.35: return "20m"
        case 18.068 ..< 18.168: return "17m"
        case 21.0 ..< 21.45: return "15m"
        case 24.89 ..< 24.99: return "12m"
        case 28.0 ..< 29.7: return "10m"
        case 50.0 ..< 54.0: return "6m"
        case 144.0 ..< 148.0: return "2m"
        case 420.0 ..< 450.0: return "70cm"
        default: return nil
        }
    }
}
