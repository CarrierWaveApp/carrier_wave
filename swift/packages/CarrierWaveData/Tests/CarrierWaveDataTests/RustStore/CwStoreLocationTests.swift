import XCTest
@testable import CarrierWaveData

// MARK: - CwStoreLocationTests

final class CwStoreLocationTests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CwStoreLocationTests-\(UUID().uuidString)")
        legacy = root.appendingPathComponent("group")
        destination = root.appendingPathComponent("private/CwStore")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testNothingToMoveUsesDestination() throws {
        let resolved = try CwStoreLocation.migrate(from: legacy, to: destination)
        XCTAssertEqual(resolved, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testMovesEveryStoreFileAndLeavesOthers() throws {
        let storeFiles = [
            "cw-store.db",
            "cw-store.db-journal",
            "cw-store.recovery.json",
            "cw-store.orphaned-1700000000.db",
            "cw-store.orphaned-1700000000.db-wal",
        ]
        for name in storeFiles {
            try write(name, in: legacy)
        }
        try write("CarrierWave.store", in: legacy)

        let resolved = try CwStoreLocation.migrate(from: legacy, to: destination)

        XCTAssertEqual(resolved, destination)
        for name in storeFiles {
            XCTAssertEqual(try read(name, in: destination), name, "\(name) should move intact")
            XCTAssertFalse(exists(name, in: legacy), "\(name) should be gone from the App Group")
        }
        XCTAssertTrue(exists("CarrierWave.store", in: legacy), "non-cw-store files stay put")
    }

    func testFirstMoveFailureFallsBackToLegacy() throws {
        try write("cw-store.db", in: legacy)
        try write("cw-store.db-journal", in: legacy)

        let resolved = try CwStoreLocation.migrate(
            from: legacy,
            to: destination,
            fileManager: FailingMoveFileManager(failAfter: 0)
        )

        XCTAssertEqual(resolved, legacy)
        XCTAssertTrue(exists("cw-store.db", in: legacy))
        XCTAssertTrue(exists("cw-store.db-journal", in: legacy))
    }

    func testPartialMoveThrowsInsteadOfSplittingStore() throws {
        try write("cw-store.db", in: legacy)
        try write("cw-store.db-journal", in: legacy)

        XCTAssertThrowsError(
            try CwStoreLocation.migrate(
                from: legacy,
                to: destination,
                fileManager: FailingMoveFileManager(failAfter: 1)
            )
        )
        // The journal (sidecars move first) made it; the database didn't.
        XCTAssertTrue(exists("cw-store.db-journal", in: destination))
        XCTAssertTrue(exists("cw-store.db", in: legacy))
    }

    func testRetryAfterPartialMoveFinishesAndNeverReturnsLegacy() throws {
        try write("cw-store.db", in: legacy)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try write("cw-store.db-journal", in: destination)

        // Even if this attempt's first move fails, the legacy directory is no
        // longer whole (its journal already moved), so it must not be returned.
        XCTAssertThrowsError(
            try CwStoreLocation.migrate(
                from: legacy,
                to: destination,
                fileManager: FailingMoveFileManager(failAfter: 0)
            )
        )

        let resolved = try CwStoreLocation.migrate(from: legacy, to: destination)
        XCTAssertEqual(resolved, destination)
        XCTAssertTrue(exists("cw-store.db", in: destination))
        XCTAssertTrue(exists("cw-store.db-journal", in: destination))
    }

    func testConflictIsNeverOverwritten() throws {
        try write("cw-store.db-journal", in: legacy)
        try write("cw-store.db", in: legacy)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "existing".write(
            to: destination.appendingPathComponent("cw-store.db"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try CwStoreLocation.migrate(from: legacy, to: destination))
        XCTAssertEqual(try read("cw-store.db", in: destination), "existing")
        XCTAssertEqual(try read("cw-store.db", in: legacy), "cw-store.db")
    }

    // MARK: Private

    private var root: URL!
    private var legacy: URL!
    private var destination: URL!

    private func write(_ name: String, in directory: URL) throws {
        try name.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func read(_ name: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    private func exists(_ name: String, in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }
}

// MARK: - FailingMoveFileManager

/// Lets `failAfter` moves succeed, then throws on every later one.
private final class FailingMoveFileManager: FileManager, @unchecked Sendable {
    // MARK: Lifecycle

    init(failAfter: Int) {
        remaining = failAfter
        super.init()
    }

    // MARK: Internal

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        guard remaining > 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        remaining -= 1
        try super.moveItem(at: srcURL, to: dstURL)
    }

    // MARK: Private

    private var remaining: Int
}
