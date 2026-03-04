import CarrierWaveData
import Foundation
import XCTest
@testable import CarrierWave

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
