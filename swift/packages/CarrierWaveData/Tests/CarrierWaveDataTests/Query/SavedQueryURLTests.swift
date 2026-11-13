import CarrierWaveData
import Foundation
import Testing

@Suite("Saved query URL scheme")
struct SavedQueryURLTests {
    @Test("encode + decode round-trip preserves the saved query")
    func roundTrip() throws {
        let original = SavedQuery(
            name: "Test Query",
            description: "round trip test",
            sql: "SELECT * FROM qsos",
            schemaVersion: QuerySchemaVersion.current,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            columnHints: ["timestamp": "timestamp"]
        )

        let url = try SavedQueryURL.encode(original)
        #expect(url.scheme == SavedQueryURL.scheme)

        let decoded = try SavedQueryURL.decode(url)
        #expect(decoded.name == original.name)
        #expect(decoded.sql == original.sql)
        #expect(decoded.schemaVersion == original.schemaVersion)
        #expect(decoded.columnHints == original.columnHints)
    }

    @Test("rejects URLs with the wrong scheme")
    func rejectsWrongScheme() throws {
        guard let bad = URL(string: "https://example.com") else {
            Issue.record("URL constructor failed")
            return
        }
        do {
            _ = try SavedQueryURL.decode(bad)
            Issue.record("expected throw")
        } catch {
            // expected
        }
    }
}
