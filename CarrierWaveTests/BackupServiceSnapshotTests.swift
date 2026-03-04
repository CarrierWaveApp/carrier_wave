import CarrierWaveData
import Foundation
import SQLite3
import XCTest
@testable import CarrierWave

@MainActor
final class BackupServiceSnapshotTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: testDir, withIntermediateDirectories: true
        )

        // Create a minimal SQLite database for testing
        testDBURL = testDir.appendingPathComponent("test.sqlite")
        createTestDatabase(at: testDBURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDir)
        try await super.tearDown()
    }

    func testSnapshotCreatesFile() async {
        let entry = await BackupService.shared.snapshot(
            trigger: .manual, storeURL: testDBURL
        )

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.trigger, .manual)
        XCTAssertEqual(entry?.location, .local)
        XCTAssertGreaterThan(entry?.sizeBytes ?? 0, 0)
    }

    func testSnapshotAppearsInAvailableBackups() async {
        _ = await BackupService.shared.snapshot(
            trigger: .manual, storeURL: testDBURL
        )

        let backups = await BackupService.shared.availableBackups()
        XCTAssertFalse(backups.isEmpty)
    }

    func testValidateRejectsCorruptFile() async {
        // Create a corrupt file
        let corruptURL = testDir.appendingPathComponent("corrupt.sqlite")
        try? Data("not a database".utf8).write(to: corruptURL)

        let entry = BackupEntry(
            id: UUID(),
            timestamp: Date(),
            trigger: .manual,
            qsoCount: 0,
            sizeBytes: 100,
            appVersion: "1.0",
            location: .local,
            filename: "corrupt.sqlite"
        )

        let result = await BackupService.shared.validateBackup(entry)
        if case .success = result {
            XCTFail("Should have failed validation")
        }
    }

    // MARK: Private

    private var testDir: URL!
    private var testDBURL: URL!

    // MARK: - Helpers

    private func createTestDatabase(at url: URL) {
        var db: OpaquePointer?
        sqlite3_open(url.path, &db)
        sqlite3_exec(
            db,
            "CREATE TABLE IF NOT EXISTS ZQSO (Z_PK INTEGER PRIMARY KEY)",
            nil, nil, nil
        )
        // Insert a few rows
        for i in 1 ... 5 {
            sqlite3_exec(
                db,
                "INSERT INTO ZQSO (Z_PK) VALUES (\(i))",
                nil, nil, nil
            )
        }
        sqlite3_close(db)
    }
}
