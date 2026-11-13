import CarrierWaveData
import Foundation
import GRDB
import Testing

@Suite("Read-only enforcement")
struct ReadOnlyEnforcementTests {
    // MARK: Internal

    @Test("INSERT through reader connection fails")
    func insertFails() async throws {
        let store = try makeStore()
        let reader = try await store.openReader()
        do {
            try await reader.write { db in
                let insertSQL = """
                INSERT INTO qsos (id, callsign, band, mode, timestamp, my_callsign)
                VALUES ('x', 'K1ABC', '20m', 'CW', 0, 'TEST')
                """
                try db.execute(sql: insertSQL)
            }
            Issue.record("expected throw")
        } catch {
            // expected
        }
    }

    @Test("DROP TABLE through reader connection fails")
    func dropFails() async throws {
        let store = try makeStore()
        let reader = try await store.openReader()
        do {
            try await reader.write { db in
                try db.execute(sql: "DROP TABLE qsos")
            }
            Issue.record("expected throw")
        } catch {
            // expected
        }
    }

    // MARK: Private

    private func makeStore() throws -> QueryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CarrierWaveQueryReadOnlyTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).sqlite")
        let scopeURL = dir.appendingPathComponent("\(UUID().uuidString)-scope.sqlite")
        return try QueryStore(databaseURL: url, scopeURL: scopeURL)
    }
}
