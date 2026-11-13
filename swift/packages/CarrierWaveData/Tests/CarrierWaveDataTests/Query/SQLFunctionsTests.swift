import CarrierWaveData
import Foundation
import GRDB
import Testing

@Suite("SQL distance functions")
struct SQLFunctionsTests {
    // MARK: Internal

    @Test("cw_distance_km matches reference distance NYC → SF")
    func haversine4ArgKm() async throws {
        let reader = try await openReader()
        let km = try await reader.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT cw_distance_km(?, ?, ?, ?)",
                arguments: [40.7128, -74.0060, 37.7749, -122.4194]
            )
        }
        // Reference: ~4129 km, accept ±5 km of rounding/sphere model.
        try #require(km != nil)
        #expect(abs((km ?? 0) - 4_129.0) < 5.0)
    }

    @Test("cw_distance_mi is km × 0.621371")
    func haversine4ArgMi() async throws {
        let reader = try await openReader()
        let (mi, km) = try await reader.read { db in
            let mi = try Double.fetchOne(
                db,
                sql: "SELECT cw_distance_mi(?, ?, ?, ?)",
                arguments: [40.7128, -74.0060, 37.7749, -122.4194]
            )
            let km = try Double.fetchOne(
                db,
                sql: "SELECT cw_distance_km(?, ?, ?, ?)",
                arguments: [40.7128, -74.0060, 37.7749, -122.4194]
            )
            return (mi, km)
        }
        try #require(mi != nil)
        try #require(km != nil)
        #expect(abs((mi ?? 0) - (km ?? 0) * 0.621371) < 0.01)
    }

    @Test("cw_grid_distance_km from FN20 to CM87 is roughly transcontinental")
    func gridDistanceKm() async throws {
        let reader = try await openReader()
        let km = try await reader.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT cw_grid_distance_km(?, ?)",
                arguments: ["FN20", "CM87"]
            )
        }
        try #require(km != nil)
        // FN20 (NJ) → CM87 (Bay Area) ≈ 4100 km. Loose bound for grid centers.
        #expect((km ?? 0) > 3_900 && (km ?? 0) < 4_300)
    }

    @Test("cw_grid_distance_km returns NULL for an invalid grid")
    func gridDistanceInvalid() async throws {
        let reader = try await openReader()
        let km = try await reader.read { db in
            try DatabaseValue.fetchOne(
                db,
                sql: "SELECT cw_grid_distance_km(?, ?)",
                arguments: ["NOPE", "CM87"]
            )
        }
        #expect(km?.isNull == true)
    }

    @Test("cw_user_grid() reflects the provider")
    func userGridProvider() async throws {
        let reader = try await openReader(userGrid: "CM87wj")
        let grid = try await reader.read { db in
            try String.fetchOne(db, sql: "SELECT cw_user_grid()")
        }
        #expect(grid == "CM87wj")
    }

    @Test("cw_user_grid_distance_km(grid) computes distance from user to grid")
    func userGridDistance() async throws {
        let reader = try await openReader(userGrid: "CM87wj")
        let km = try await reader.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT cw_user_grid_distance_km(?)",
                arguments: ["FN20"]
            )
        }
        try #require(km != nil)
        #expect((km ?? 0) > 3_900 && (km ?? 0) < 4_300)
    }

    @Test("cw_user_distance_km(lat, lon) computes distance from user to coord")
    func userCoordDistance() async throws {
        let reader = try await openReader(userGrid: "CM87wj")
        let km = try await reader.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT cw_user_distance_km(?, ?)",
                arguments: [40.7128, -74.0060]
            )
        }
        try #require(km != nil)
        // CM87wj (~37.7°N -122.4°W) → NYC ~4130 km
        #expect((km ?? 0) > 3_900 && (km ?? 0) < 4_300)
    }

    @Test("cw_user_grid_distance_km returns NULL when user grid is unset")
    func userDistanceWithoutUserGrid() async throws {
        let reader = try await openReader(userGrid: nil)
        let value = try await reader.read { db in
            try DatabaseValue.fetchOne(
                db,
                sql: "SELECT cw_user_grid_distance_km(?)",
                arguments: ["FN20"]
            )
        }
        #expect(value?.isNull == true)
    }

    @Test("filter spotters within 50km using cw_user_distance_km")
    func filterSpottersWithin50Km() async throws {
        let store = try makeStore(userGrid: "CM87wj")
        // Seed spotters: one in San Francisco (close), one in NYC (far).
        try await store.upsertSpotter(SpotterRow(
            callsign: "K6NEAR",
            grid: "CM87wj",
            lat: 37.78,
            lon: -122.42,
            dxccEntity: nil,
            continent: nil,
            isSkimmer: false
        ))
        try await store.upsertSpotter(SpotterRow(
            callsign: "K1FAR",
            grid: "FN30",
            lat: 40.71,
            lon: -74.01,
            dxccEntity: nil,
            continent: nil,
            isSkimmer: false
        ))
        let reader = try await store.openReader()
        let calls = try await reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT callsign FROM scope.spotters
                WHERE cw_user_distance_km(lat, lon) < 50
                ORDER BY callsign
                """
            )
        }
        #expect(calls == ["K6NEAR"])
    }

    @Test("sort spotters by nearest using cw_user_grid_distance_km")
    func sortSpottersByNearest() async throws {
        let store = try makeStore(userGrid: "CM87wj")
        try await store.upsertSpotter(SpotterRow(
            callsign: "K1FAR",
            grid: "FN30",
            lat: 40.71,
            lon: -74.01,
            dxccEntity: nil,
            continent: nil,
            isSkimmer: false
        ))
        try await store.upsertSpotter(SpotterRow(
            callsign: "K6NEAR",
            grid: "CM87wj",
            lat: 37.78,
            lon: -122.42,
            dxccEntity: nil,
            continent: nil,
            isSkimmer: false
        ))
        let reader = try await store.openReader()
        let order = try await reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT callsign FROM scope.spotters
                ORDER BY cw_user_grid_distance_km(grid) ASC NULLS LAST
                """
            )
        }
        #expect(order == ["K6NEAR", "K1FAR"])
    }

    // MARK: Private

    private func openReader(userGrid: String? = nil) async throws -> DatabaseQueue {
        let store = try makeStore(userGrid: userGrid)
        return try await store.openReader()
    }

    private func makeStore(userGrid: String?) throws -> QueryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CarrierWaveSQLFunctionsTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).sqlite")
        let scopeURL = dir.appendingPathComponent("\(UUID().uuidString)-scope.sqlite")
        let provider: @Sendable () -> String? = { userGrid }
        return try QueryStore(
            databaseURL: url,
            scopeURL: scopeURL,
            userGridProvider: provider
        )
    }
}
