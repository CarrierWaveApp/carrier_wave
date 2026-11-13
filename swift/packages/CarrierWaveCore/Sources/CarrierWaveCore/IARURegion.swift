// IARU Region
//
// Amateur radio is coordinated by three IARU regions with distinct band
// plans and calling frequencies. Used by the band plan, propagation, and
// contest features to localize frequency suggestions.

import Foundation

// MARK: - IARURegion

/// The three IARU regions. Region numbers follow ITU usage.
public enum IARURegion: Int, CaseIterable, Sendable, Codable {
    /// Europe, Africa, Middle East, and northern Asia (including all of Russia).
    case region1 = 1
    /// The Americas and Greenland.
    case region2 = 2
    /// Asia-Pacific south of 40° N, Australia, and most of Oceania.
    case region3 = 3

    // MARK: Public

    /// Human-readable short name.
    public var displayName: String {
        switch self {
        case .region1: "IARU Region 1"
        case .region2: "IARU Region 2"
        case .region3: "IARU Region 3"
        }
    }

    /// Coarse geographic description for settings copy.
    public var regionDescription: String {
        switch self {
        case .region1: "Europe, Africa, Middle East"
        case .region2: "Americas"
        case .region3: "Asia-Pacific, Oceania"
        }
    }

    /// Derive the IARU region from the representative coordinate of a DXCC
    /// entity. The ITU dividing lines are approximate — a boundary-straddling
    /// operator may need to override manually.
    public static func from(latitude: Double, longitude: Double) -> IARURegion {
        if longitude >= -30, longitude < 60 {
            return .region1
        }
        if longitude >= -170, longitude < -30 {
            return .region2
        }
        if longitude >= 60, longitude < 180, latitude < 40 {
            return .region3
        }
        // Northern Asia / Russia east of 60° E is Region 1 by IARU convention.
        if longitude >= 60, latitude >= 40 {
            return .region1
        }
        return .region2
    }

    /// Derive the IARU region from a callsign's DXCC entity.
    /// Returns nil if the callsign can't be resolved.
    public static func from(callsign: String) -> IARURegion? {
        guard let country = LocationPrefixLookup.entity(forCallsign: callsign) else {
            return nil
        }
        return from(latitude: country.latitude, longitude: country.longitude)
    }

    /// Derive the IARU region from a Maidenhead grid square.
    public static func from(grid: String) -> IARURegion? {
        guard let coord = MaidenheadConverter.coordinate(from: grid) else {
            return nil
        }
        return from(latitude: coord.latitude, longitude: coord.longitude)
    }
}
