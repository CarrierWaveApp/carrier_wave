import Foundation
import SQLite3
import XCTest
@testable import CarrierWave

final class BackupServiceIntegrityTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: testDir, withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
        super.tearDown()
    }

    func testValidateAcceptsValidDatabase() async throws {
        let dbURL = testDir.appendingPathComponent("valid.sqlite")
        var db: OpaquePointer?
        sqlite3_open(dbURL.path, &db)
        sqlite3_exec(
            db,
            "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)",
            nil, nil, nil
        )
        sqlite3_exec(
            db,
            "INSERT INTO test VALUES (1, 'hello')",
            nil, nil, nil
        )
        sqlite3_close(db)

        // Copy to backup dir so validation can find it
        let library = try XCTUnwrap(FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first)
        let backupDir = library.appendingPathComponent("Backups")
        try? FileManager.default.createDirectory(
            at: backupDir, withIntermediateDirectories: true
        )
        let backupURL = backupDir.appendingPathComponent("valid_test.sqlite")
        try? FileManager.default.copyItem(at: dbURL, to: backupURL)
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let entry = BackupEntry(
            id: UUID(),
            timestamp: Date(),
            trigger: .manual,
            qsoCount: 1,
            sizeBytes: 1_000,
            appVersion: "1.0",
            location: .local,
            filename: "valid_test.sqlite"
        )

        let result = await BackupService.shared.validateBackup(entry)
        if case .failure = result {
            XCTFail("Should have passed validation")
        }
    }

    // MARK: Private

    private var testDir: URL!
}
