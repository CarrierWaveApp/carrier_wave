//
//  BandUtilities.swift
//  CarrierWaveCore
//
//  Delegates to `cw-domain::band::BandUtilities` via the UniFFI surface.
//

import CarrierWaveCwFfi
import Foundation

/// Utility for band-related operations
public enum BandUtilities: Sendable {
    /// Band order for sorting (frequency order low to high)
    public static let bandOrder: [String] = bandOrderList()

    /// Bands the user is most likely to operate, in display order.
    public static let standardBands: [String] = standardBandsList()

    /// Approximate top of CW/digital portion of an HF band (lower-edge → here).
    public static func digitalBoundaryKHz(forBand band: String) -> Double? {
        bandDigitalBoundaryKhz(band: band)
    }

    /// Approximate start of SSB/phone portion of an HF band (here → upper-edge).
    public static func ssbBoundaryKHz(forBand band: String) -> Double? {
        bandSsbBoundaryKhz(band: band)
    }

    /// Frequency range (in MHz) for a given amateur radio band.
    /// Used by visual scope / band map views to map between Hz and screen
    /// coordinates. Returns nil for unknown bands.
    public static func range(forBand band: String) -> (lowMHz: Double, highMHz: Double)? {
        bandRange(band: band).map { ($0.lowMhz, $0.highMhz) }
    }

    /// Derives the amateur radio band from a frequency in kHz
    /// - Parameter frequencyKHz: Frequency in kilohertz
    /// - Returns: Band designation (e.g., "20m") or nil if not a recognized band
    public static func deriveBand(from frequencyKHz: Double?) -> String? {
        guard let kHz = frequencyKHz else {
            return nil
        }
        return bandDerive(frequencyKhz: kHz)
    }
}
