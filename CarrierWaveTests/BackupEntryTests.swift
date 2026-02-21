import Foundation
import XCTest
@testable import CarrierWave

final class BackupEntryTests: XCTestCase {
    func testManifestRoundTrip() throws {
        let entries = [
            BackupEntry(
                id: UUID(),
                timestamp: Date(),
                trigger: .launch,
                qsoCount: 100,
                sizeBytes: 5_000_000,
                appVersion: "1.41.0",
                location: .local,
                filename: "carrierwave_2026-02-20_120000.sqlite"
            ),
            BackupEntry(
                id: UUID(),
                timestamp: Date().addingTimeInterval(-3_600),
                trigger: .manual,
                qsoCount: 95,
                sizeBytes: 4_800_000,
                appVersion: "1.40.0",
                location: .icloud,
                filename: "carrierwave_2026-02-19_120000.sqlite"
            ),
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(entries)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([BackupEntry].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].id, entries[0].id)
        XCTAssertEqual(decoded[0].trigger, .launch)
        XCTAssertEqual(decoded[0].qsoCount, 100)
        XCTAssertEqual(decoded[0].sizeBytes, 5_000_000)
        XCTAssertEqual(decoded[0].appVersion, "1.41.0")
        XCTAssertEqual(decoded[0].location, .local)
        XCTAssertEqual(decoded[0].filename, entries[0].filename)

        XCTAssertEqual(decoded[1].trigger, .manual)
        XCTAssertEqual(decoded[1].location, .icloud)
    }

    func testAllTriggersEncodeDecode() throws {
        let triggers: [BackupTrigger] = [
            .launch, .preSync, .preImport, .manual, .preRestore,
        ]

        for trigger in triggers {
            let entry = BackupEntry(
                id: UUID(),
                timestamp: Date(),
                trigger: trigger,
                qsoCount: 50,
                sizeBytes: 1_000,
                appVersion: "1.0",
                location: .local,
                filename: "test.sqlite"
            )

            let data = try JSONEncoder().encode(entry)
            let decoded = try JSONDecoder().decode(
                BackupEntry.self, from: data
            )
            XCTAssertEqual(decoded.trigger, trigger)
        }
    }
}
