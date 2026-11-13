import CarrierWaveData
import CoreLocation

/// Converts Maidenhead grid locators to coordinates
/// Wraps CarrierWaveCore's MaidenheadConverter to provide CLLocationCoordinate2D
nonisolated enum MaidenheadConverter {
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

    /// Convert a coordinate to a Maidenhead grid locator at the requested precision.
    /// Defaults to 6-character for back-compat with existing call sites.
    nonisolated static func grid(
        from coordinate: CLLocationCoordinate2D,
        precision: CarrierWaveCore.MaidenheadConverter.Precision = .six
    ) -> String {
        CarrierWaveCore.MaidenheadConverter.grid(
            from: Coordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            precision: precision
        )
    }

    /// Check if a grid locator string is valid
    nonisolated static func isValid(_ grid: String) -> Bool {
        CarrierWaveCore.MaidenheadConverter.isValid(grid)
    }

    /// Distance in kilometers between two Maidenhead grid squares
    nonisolated static func distanceKm(from grid1: String, to grid2: String) -> Double? {
        CarrierWaveCore.MaidenheadConverter.distanceKm(from: grid1, to: grid2)
    }

    /// Distance in miles between two Maidenhead grid squares
    nonisolated static func distanceMiles(from grid1: String, to grid2: String) -> Double? {
        CarrierWaveCore.MaidenheadConverter.distanceMiles(from: grid1, to: grid2)
    }

    /// Initial bearing in degrees from one grid to another
    nonisolated static func bearing(from grid1: String, to grid2: String) -> Double? {
        CarrierWaveCore.MaidenheadConverter.bearing(from: grid1, to: grid2)
    }

    /// Returns the SW and NE corners of a 4-char grid square as CLLocationCoordinate2D
    nonisolated static func gridBounds(
        for grid: String
    ) -> (sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D)? {
        guard let bounds = CarrierWaveCore.MaidenheadConverter.gridBounds(for: grid) else {
            return nil
        }
        return (
            sw: CLLocationCoordinate2D(latitude: bounds.sw.latitude, longitude: bounds.sw.longitude),
            ne: CLLocationCoordinate2D(latitude: bounds.ne.latitude, longitude: bounds.ne.longitude)
        )
    }

    /// Returns the SW and NE corners of a 6-char Maidenhead tile as
    /// CLLocationCoordinate2D, used by the TOTA path map's tile-boundary overlay.
    nonisolated static func tileBounds(
        for tile: String
    ) -> (sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D)? {
        guard let bounds = CarrierWaveCore.MaidenheadConverter.tileBounds(for: tile) else {
            return nil
        }
        return (
            sw: CLLocationCoordinate2D(latitude: bounds.sw.latitude, longitude: bounds.sw.longitude),
            ne: CLLocationCoordinate2D(latitude: bounds.ne.latitude, longitude: bounds.ne.longitude)
        )
    }

    /// Enumerate all 4-char grids visible within a map region
    nonisolated static func gridsInRegion(
        sw: CLLocationCoordinate2D,
        ne: CLLocationCoordinate2D
    ) -> [String] {
        CarrierWaveCore.MaidenheadConverter.gridsInRegion(
            sw: Coordinate(latitude: sw.latitude, longitude: sw.longitude),
            ne: Coordinate(latitude: ne.latitude, longitude: ne.longitude)
        )
    }
}
