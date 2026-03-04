import CarrierWaveData
import Foundation
import XCTest
@testable import CarrierWave

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
        try Data("garbage".utf8).write(
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
