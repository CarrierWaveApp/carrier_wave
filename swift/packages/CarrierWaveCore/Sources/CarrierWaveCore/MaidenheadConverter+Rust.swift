import CarrierWaveCwFfi
import Foundation

// Bridge to `cw-domain::maidenhead` via the UniFFI surface.
//
// Phase-2 mechanical port (see `docs/plans/2026-06-13-rust-core-handoff.md`).
// Keeps the Swift signatures, forwards through Rust, lifts the result back
// into Swift's native `Coordinate` / `Precision` types. Parity is asserted
// in `MaidenheadConverterRustParityTests`.

public extension MaidenheadConverter {
    /// Center coordinate of a Maidenhead grid via Rust. Returns nil for invalid input.
    static func coordinateViaRust(from grid: String) -> Coordinate? {
        maidenheadCoordinate(grid: grid).map(liftCoordinate)
    }

    /// Encode a coordinate as a Maidenhead grid via Rust at the requested precision.
    static func gridViaRust(
        from coordinate: Coordinate,
        precision: Precision = .six
    ) -> String {
        maidenheadGrid(
            coordinate: lowerCoordinate(coordinate),
            precision: lowerPrecision(precision)
        )
    }

    /// Great-circle distance in km via Rust. Returns nil if either grid is invalid.
    static func distanceKmViaRust(from grid1: String, to grid2: String) -> Double? {
        maidenheadDistanceKm(grid1: grid1, grid2: grid2)
    }

    /// Initial bearing in degrees `[0, 360)` via Rust. Returns nil for invalid input.
    static func bearingViaRust(from grid1: String, to grid2: String) -> Double? {
        maidenheadBearing(grid1: grid1, grid2: grid2)
    }

    /// Grid validity check via Rust.
    static func isValidViaRust(_ grid: String) -> Bool {
        maidenheadIsValid(grid: grid)
    }

    // MARK: Private

    private static func liftCoordinate(_ ffi: FfiCoordinate) -> Coordinate {
        Coordinate(latitude: ffi.latitude, longitude: ffi.longitude)
    }

    private static func lowerCoordinate(_ coord: Coordinate) -> FfiCoordinate {
        FfiCoordinate(latitude: coord.latitude, longitude: coord.longitude)
    }

    private static func lowerPrecision(_ precision: Precision) -> FfiMaidenheadPrecision {
        switch precision {
        case .four: .four
        case .six: .six
        case .eight: .eight
        }
    }
}
