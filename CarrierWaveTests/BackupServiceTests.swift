import Foundation
import SQLite3
import XCTest
@testable import CarrierWave

// MARK: - BackupEntryTests

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
                timestamp: Date().addingTimeInterval(-3600),
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
                sizeBytes: 1000,
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

// MARK: - PendingRestoreTests

final class PendingRestoreTests: XCTestCase {
    func testPendingRestoreRoundTrip() throws {
        let pending = PendingRestore(
            backupFilename: "carrierwave_2026-02-20_120000.sqlite",
            backupTimestamp: Date(),
            stagedAt: Date()
        )

        let data = try JSONEncoder().encode(pending)
        let decoded = try JSONDecoder().decode(
            PendingRestore.self, from: data
        )

        XCTAssertEqual(decoded.backupFilename, pending.backupFilename)
    }
}

// MARK: - BackupServiceSnapshotTests

final class BackupServiceSnapshotTests: XCTestCase {
    private var testDir: URL!
    private var testDBURL: URL!

    override func setUp() {
        super.setUp()
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: testDir, withIntermediateDirectories: true
        )

        // Create a minimal SQLite database for testing
        testDBURL = testDir.appendingPathComponent("test.sqlite")
        createTestDatabase(at: testDBURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
        super.tearDown()
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
        try? "not a database".data(using: .utf8)?.write(to: corruptURL)

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

// MARK: - BackupServiceIntegrityTests

final class BackupServiceIntegrityTests: XCTestCase {
    private var testDir: URL!

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

    func testValidateAcceptsValidDatabase() async {
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
        let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!
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
            sizeBytes: 1000,
            appVersion: "1.0",
            location: .local,
            filename: "valid_test.sqlite"
        )

        let result = await BackupService.shared.validateBackup(entry)
        if case .failure = result {
            XCTFail("Should have passed validation")
        }
    }
}

// MARK: - PendingRestoreMarkerTests

final class PendingRestoreMarkerTests: XCTestCase {
    override func tearDown() {
        try? FileManager.default.removeItem(
            at: BackupService.pendingRestoreURL
        )
        super.tearDown()
    }

    func testCheckPendingRestoreReturnsNilWhenNoMarker() {
        // Ensure no marker file exists
        try? FileManager.default.removeItem(
            at: BackupService.pendingRestoreURL
        )

        let result = BackupService.checkPendingRestore()
        XCTAssertNil(result)
    }

    func testCheckPendingRestoreReadsMarker() throws {
        let pending = PendingRestore(
            backupFilename: "test_backup.sqlite",
            backupTimestamp: Date(),
            stagedAt: Date()
        )

        let data = try JSONEncoder().encode(pending)
        try data.write(to: BackupService.pendingRestoreURL)

        let result = BackupService.checkPendingRestore()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.backupFilename, "test_backup.sqlite")
    }

    func testCheckPendingRestoreClearsCorruptMarker() throws {
        try "garbage".data(using: .utf8)?.write(
            to: BackupService.pendingRestoreURL
        )

        let result = BackupService.checkPendingRestore()
        XCTAssertNil(result)

        // Marker should be cleaned up
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: BackupService.pendingRestoreURL.path
            )
        )
    }
}
