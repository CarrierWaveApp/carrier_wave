//
//  MaidenheadConverter.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - Coordinate

/// A simple latitude/longitude coordinate (platform-agnostic alternative to CLLocationCoordinate2D)
public struct Coordinate: Sendable, Equatable {
    // MARK: Lifecycle

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    // MARK: Public

    public let latitude: Double
    public let longitude: Double
}

// MARK: - MaidenheadConverter

/// Converts Maidenhead grid locators to coordinates
public enum MaidenheadConverter: Sendable {
    /// Convert a Maidenhead grid locator to coordinates (center of grid square)
    /// Supports 4-char (e.g., "FN31") and 6-char (e.g., "FN31pr") formats
    /// - Parameter grid: The grid locator string (case insensitive)
    /// - Returns: The center coordinate of the grid square, or nil if invalid
    public static func coordinate(from grid: String) -> Coordinate? {
        let grid = grid.uppercased()

        guard grid.count >= 4 else {
            return nil
        }

        let chars = Array(grid)

        // Field (first 2 chars): A-R for both longitude and latitude
        guard let lonField = chars[0].asciiValue.map({ Int($0) - 65 }),
              let latField = chars[1].asciiValue.map({ Int($0) - 65 }),
              lonField >= 0, lonField < 18,
              latField >= 0, latField < 18
        else {
            return nil
        }

        // Square (next 2 chars): 0-9 for both longitude and latitude
        guard let lonSquare = chars[2].wholeNumberValue,
              let latSquare = chars[3].wholeNumberValue
        else {
            return nil
        }

        // Calculate base coordinates
        var longitude = Double(lonField * 20 - 180 + lonSquare * 2)
        var latitude = Double(latField * 10 - 90 + latSquare)

        // Subsquare (optional 5th and 6th chars): a-x for both
        if grid.count >= 6 {
            guard let lonSubsquare = chars[4].asciiValue.map({ Int($0) - 65 }),
                  let latSubsquare = chars[5].asciiValue.map({ Int($0) - 65 }),
                  lonSubsquare >= 0, lonSubsquare < 24,
                  latSubsquare >= 0, latSubsquare < 24
            else {
                // Invalid subsquare, just use 4-char grid center
                longitude += 1.0 // Center of 2-degree square
                latitude += 0.5 // Center of 1-degree square
                return Coordinate(latitude: latitude, longitude: longitude)
            }

            // Add subsquare offset (each subsquare is 5 minutes longitude, 2.5 minutes latitude)
            longitude += Double(lonSubsquare) * (2.0 / 24.0) + (1.0 / 24.0)
            latitude += Double(latSubsquare) * (1.0 / 24.0) + (0.5 / 24.0)
        } else {
            // Center of 4-char grid
            longitude += 1.0 // Center of 2-degree square
            latitude += 0.5 // Center of 1-degree square
        }

        return Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Check if a grid locator string is valid
    public static func isValid(_ grid: String) -> Bool {
        coordinate(from: grid) != nil
    }
}
