import CarrierWaveCore
import CoreLocation

/// Converts Maidenhead grid locators to coordinates
/// Wraps CarrierWaveCore's MaidenheadConverter to provide CLLocationCoordinate2D
enum MaidenheadConverter {
    /// Convert a Maidenhead grid locator to coordinates (center of grid square)
    /// Supports 4-char (e.g., "FN31") and 6-char (e.g., "FN31pr") formats
    /// - Parameter grid: The grid locator string (case insensitive)
    /// - Returns: The center coordinate of the grid square, or nil if invalid
    nonisolated static func coordinate(from grid: String) -> CLLocationCoordinate2D? {
        guard let coord = CarrierWaveCore.MaidenheadConverter.coordinate(from: grid) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    /// Convert a coordinate to a 6-character Maidenhead grid locator
    nonisolated static func grid(from coordinate: CLLocationCoordinate2D) -> String {
        CarrierWaveCore.MaidenheadConverter.grid(
            from: Coordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        )
    }

    /// Check if a grid locator string is valid
    nonisolated static func isValid(_ grid: String) -> Bool {
        CarrierWaveCore.MaidenheadConverter.isValid(grid)
    }
}
