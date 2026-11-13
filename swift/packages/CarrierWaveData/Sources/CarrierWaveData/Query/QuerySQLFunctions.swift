import CarrierWaveCore
import Foundation
import GRDB

// MARK: - QuerySQLFunctions

/// Custom SQL functions registered on every QueryReader connection so
/// SQL written in the Query Workbench can compute great-circle distance
/// and bearing without leaving the database.
///
/// All functions return `NULL` rather than throwing on bad inputs
/// (invalid grid, NULL coordinate, etc.) so they compose cleanly with
/// `ORDER BY ... NULLS LAST` and `WHERE ... < 50` style filters.
///
/// Available signatures:
///   cw_distance_km(lat1, lon1, lat2, lon2)         — haversine, km
///   cw_distance_mi(lat1, lon1, lat2, lon2)         — haversine, mi
///   cw_bearing_deg(lat1, lon1, lat2, lon2)         — initial bearing, deg
///   cw_grid_distance_km(grid1, grid2)              — Maidenhead, km
///   cw_grid_distance_mi(grid1, grid2)              — Maidenhead, mi
///   cw_grid_bearing_deg(grid1, grid2)              — Maidenhead, deg
///   cw_user_grid()                                 — configured user grid
///   cw_user_grid_distance_km(grid)                 — user → grid, km
///   cw_user_grid_distance_mi(grid)                 — user → grid, mi
///   cw_user_grid_bearing_deg(grid)                 — user → grid, deg
///   cw_user_distance_km(lat, lon)                  — user → coord, km
///   cw_user_distance_mi(lat, lon)                  — user → coord, mi
///   cw_user_bearing_deg(lat, lon)                  — user → coord, deg
///   cw_now()                                       — Unix epoch seconds (REAL)
public enum QuerySQLFunctions {
    // MARK: Public

    /// Source of the user's currently-configured Maidenhead grid. Looked
    /// up on every call rather than captured once so changes to the
    /// grid in Settings take effect without reopening the database.
    public typealias UserGridProvider = @Sendable () -> String?

    /// Default provider that reads `myGrid` out of standard UserDefaults
    /// — the same key used by `WorkspaceView` and `SpotAggregator`.
    public static let defaultUserGridProvider: UserGridProvider = {
        let value = UserDefaults.standard.string(forKey: "myGrid") ?? ""
        return value.isEmpty ? nil : value
    }

    /// Register every `cw_*` function on the supplied database connection.
    /// Call from `prepareDatabase` so the functions follow the connection
    /// for its full lifetime.
    public static func register(
        on db: Database,
        userGridProvider: @escaping UserGridProvider
    ) {
        for fn in functions(userGridProvider: userGridProvider) {
            db.add(function: fn)
        }
    }

    // MARK: Internal

    // MARK: - Function table

    /// Build the array of `DatabaseFunction`s. Exposed for tests so they
    /// can register against an arbitrary in-memory queue.
    static func functions(
        userGridProvider: @escaping UserGridProvider
    ) -> [DatabaseFunction] {
        [
            distanceFunction(name: "cw_distance_km", inMiles: false),
            distanceFunction(name: "cw_distance_mi", inMiles: true),
            bearingFunction(name: "cw_bearing_deg"),
            gridDistanceFunction(name: "cw_grid_distance_km", inMiles: false),
            gridDistanceFunction(name: "cw_grid_distance_mi", inMiles: true),
            gridBearingFunction(name: "cw_grid_bearing_deg"),
            userGridFunction(provider: userGridProvider),
            userGridDistanceFunction(
                name: "cw_user_grid_distance_km",
                inMiles: false,
                provider: userGridProvider
            ),
            userGridDistanceFunction(
                name: "cw_user_grid_distance_mi",
                inMiles: true,
                provider: userGridProvider
            ),
            userCoordDistanceFunction(
                name: "cw_user_distance_km",
                inMiles: false,
                provider: userGridProvider
            ),
            userCoordDistanceFunction(
                name: "cw_user_distance_mi",
                inMiles: true,
                provider: userGridProvider
            ),
            userGridBearingFunction(
                name: "cw_user_grid_bearing_deg",
                provider: userGridProvider
            ),
            userCoordBearingFunction(
                name: "cw_user_bearing_deg",
                provider: userGridProvider
            ),
            nowFunction(),
        ]
    }

    // MARK: Private

    // MARK: - Math

    private static let earthRadiusKm = 6_371.0
    private static let milesPerKm = 0.621371

    /// Wall-clock now as Unix epoch seconds (REAL). Matches the
    /// convention used by every timestamp column in the schema —
    /// `last_seen_at`, `received_at`, `qsos.timestamp` are all
    /// `strftime('%s', ...)`-style epoch seconds. `pure: false` so
    /// SQLite re-evaluates on every row instead of caching the value
    /// from the first call.
    private static func nowFunction() -> DatabaseFunction {
        DatabaseFunction("cw_now", argumentCount: 0, pure: false) { _ in
            Date().timeIntervalSince1970
        }
    }

    // MARK: - Builders

    private static func distanceFunction(name: String, inMiles: Bool) -> DatabaseFunction {
        DatabaseFunction(name, argumentCount: 4, pure: true) { values in
            guard let lat1 = doubleValue(values[0]),
                  let lon1 = doubleValue(values[1]),
                  let lat2 = doubleValue(values[2]),
                  let lon2 = doubleValue(values[3])
            else {
                return nil
            }
            let km = haversineKm(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
            return inMiles ? km * milesPerKm : km
        }
    }

    private static func bearingFunction(name: String) -> DatabaseFunction {
        DatabaseFunction(name, argumentCount: 4, pure: true) { values in
            guard let lat1 = doubleValue(values[0]),
                  let lon1 = doubleValue(values[1]),
                  let lat2 = doubleValue(values[2]),
                  let lon2 = doubleValue(values[3])
            else {
                return nil
            }
            return initialBearingDeg(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
        }
    }

    private static func gridDistanceFunction(name: String, inMiles: Bool) -> DatabaseFunction {
        DatabaseFunction(name, argumentCount: 2, pure: true) { values in
            guard let grid1 = stringValue(values[0]),
                  let grid2 = stringValue(values[1]),
                  let coord1 = MaidenheadConverter.coordinate(from: grid1),
                  let coord2 = MaidenheadConverter.coordinate(from: grid2)
            else {
                return nil
            }
            let km = haversineKm(
                lat1: coord1.latitude, lon1: coord1.longitude,
                lat2: coord2.latitude, lon2: coord2.longitude
            )
            return inMiles ? km * milesPerKm : km
        }
    }

    private static func gridBearingFunction(name: String) -> DatabaseFunction {
        DatabaseFunction(name, argumentCount: 2, pure: true) { values in
            guard let grid1 = stringValue(values[0]),
                  let grid2 = stringValue(values[1]),
                  let coord1 = MaidenheadConverter.coordinate(from: grid1),
                  let coord2 = MaidenheadConverter.coordinate(from: grid2)
            else {
                return nil
            }
            return initialBearingDeg(
                lat1: coord1.latitude, lon1: coord1.longitude,
                lat2: coord2.latitude, lon2: coord2.longitude
            )
        }
    }

    private static func userGridFunction(provider: @escaping UserGridProvider) -> DatabaseFunction {
        DatabaseFunction("cw_user_grid", argumentCount: 0, pure: false) { _ in
            provider()
        }
    }

    private static func userGridDistanceFunction(
        name: String,
        inMiles: Bool,
        provider: @escaping UserGridProvider
    ) -> DatabaseFunction {
        DatabaseFunction(name, argumentCount: 1, pure: false) { values in
            guard let userGrid = provider(),
                  let userCoord = MaidenheadConverter.coordinate(from: userGrid),
                  let grid = stringValue(values[0]),
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            let km = haversineKm(
                lat1: userCoord.latitude, lon1: userCoord.longitude,
                lat2: coord.latitude, lon2: coord.longitude
            )
            return inMiles ? km * milesPerKm : km
        }
    }

    private static func userCoordDistanceFunction(
        name: String,
        inMiles: Bool,
        provider: @escaping UserGridProvider
    ) -> DatabaseFunction {
        DatabaseFunction(name, argumentCount: 2, pure: false) { values in
            guard let userGrid = provider(),
                  let userCoord = MaidenheadConverter.coordinate(from: userGrid),
                  let lat = doubleValue(values[0]),
                  let lon = doubleValue(values[1])
            else {
                return nil
            }
            let km = haversineKm(
                lat1: userCoord.latitude, lon1: userCoord.longitude,
                lat2: lat, lon2: lon
            )
            return inMiles ? km * milesPerKm : km
        }
    }

    private static func userGridBearingFunction(
        name: String,
        provider: @escaping UserGridProvider
    ) -> DatabaseFunction {
        DatabaseFunction(name, argumentCount: 1, pure: false) { values in
            guard let userGrid = provider(),
                  let userCoord = MaidenheadConverter.coordinate(from: userGrid),
                  let grid = stringValue(values[0]),
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            return initialBearingDeg(
                lat1: userCoord.latitude, lon1: userCoord.longitude,
                lat2: coord.latitude, lon2: coord.longitude
            )
        }
    }

    private static func userCoordBearingFunction(
        name: String,
        provider: @escaping UserGridProvider
    ) -> DatabaseFunction {
        DatabaseFunction(name, argumentCount: 2, pure: false) { values in
            guard let userGrid = provider(),
                  let userCoord = MaidenheadConverter.coordinate(from: userGrid),
                  let lat = doubleValue(values[0]),
                  let lon = doubleValue(values[1])
            else {
                return nil
            }
            return initialBearingDeg(
                lat1: userCoord.latitude, lon1: userCoord.longitude,
                lat2: lat, lon2: lon
            )
        }
    }

    private static func haversineKm(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let phi1 = lat1 * .pi / 180.0
        let phi2 = lat2 * .pi / 180.0
        let dPhi = (lat2 - lat1) * .pi / 180.0
        let dLambda = (lon2 - lon1) * .pi / 180.0
        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        let angular = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * angular
    }

    private static func initialBearingDeg(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let phi1 = lat1 * .pi / 180.0
        let phi2 = lat2 * .pi / 180.0
        let dLambda = (lon2 - lon1) * .pi / 180.0
        let xPart = sin(dLambda) * cos(phi2)
        let yPart = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        let bearing = atan2(xPart, yPart) * 180.0 / .pi
        return (bearing + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    // MARK: - Argument coercion

    /// Pull a Double out of a SQLite value, accepting integer storage too.
    /// SQLite numeric affinity means a column declared REAL can still
    /// hold integer storage — coerce both.
    private static func doubleValue(_ value: DatabaseValue) -> Double? {
        switch value.storage {
        case .null: nil
        case let .int64(int): Double(int)
        case let .double(dbl): dbl
        case let .string(str): Double(str)
        case .blob: nil
        }
    }

    private static func stringValue(_ value: DatabaseValue) -> String? {
        switch value.storage {
        case .null: nil
        case let .string(str): str.isEmpty ? nil : str
        case .int64,
             .double,
             .blob: nil
        }
    }
}
