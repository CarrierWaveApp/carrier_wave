import CarrierWaveData
import Foundation
import GRDB
import Testing

struct MigrationRoundtripTests {
    // MARK: Internal

    @Test("v1 migrator creates expected tables and view")
    func v1CreatesSchema() async throws {
        let store = try makeTempStore()
        let reader = try await store.openReader()

        let tables = try await reader.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
        }
        #expect(tables.contains("qsos"))
        #expect(tables.contains("dxcc"))
        #expect(tables.contains("polo_notes"))
        #expect(tables.contains("meta"))

        let views = try await reader.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='view' ORDER BY name"
            )
        }
        #expect(views.contains("dxcc_status"))
    }

    @Test("v2 migrator adds operator_profiles table")
    func v2AddsOperatorProfiles() async throws {
        let store = try makeTempStore()
        let reader = try await store.openReader()

        let tables = try await reader.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
        }
        #expect(tables.contains("operator_profiles"))

        let row = OperatorProfileRow(
            callsign: "AA7BQ",
            name: "Fred Lloyd",
            qth: "Scottsdale",
            state: "AZ",
            country: "United States",
            grid: "DM43",
            licenseClass: "Extra",
            source: "qrz",
            enrichedAt: Date()
        )
        try await store.upsertOperatorProfile(row)
        let fetched = try await store.operatorProfile(callsign: "aa7bq")
        #expect(fetched?.callsign == "AA7BQ")
        #expect(fetched?.name == "Fred Lloyd")
        #expect(fetched?.grid == "DM43")
    }

    @Test("re-opening the same DB is idempotent")
    func reopenIsIdempotent() throws {
        let url = uniqueTempURL(suffix: ".sqlite")
        let scopeURL = uniqueTempURL(suffix: "-scope.sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: scopeURL)
        }
        _ = try QueryStore(databaseURL: url, scopeURL: scopeURL)
        // Open twice — should not crash or duplicate tables.
        _ = try QueryStore(databaseURL: url, scopeURL: scopeURL)
    }

    // MARK: Private

    private func makeTempStore() throws -> QueryStore {
        let url = uniqueTempURL(suffix: ".sqlite")
        let scopeURL = uniqueTempURL(suffix: "-scope.sqlite")
        return try QueryStore(databaseURL: url, scopeURL: scopeURL)
    }

    private func uniqueTempURL(suffix: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CarrierWaveQueryTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(UUID().uuidString)\(suffix)")
    }
}
