import XCTest
@testable import CarrierWave

/// POTA lets the uploader delete a log for 24 hours after uploading it.
/// `/user/jobs` reports the time left per job as `selfDeleteSecondsRemaining`.
@MainActor
final class POTAReplaceUploadTests: XCTestCase {
    // MARK: Internal

    func testDecodesSelfDeleteWindow() throws {
        let asNumber = try decode(status: 2, selfDelete: "3600")
        XCTAssertEqual(asNumber.selfDeleteSecondsRemaining(), 3_600, accuracy: 5)

        let asString = try decode(status: 2, selfDelete: "\"1800\"")
        XCTAssertEqual(asString.selfDeleteSecondsRemaining(), 1_800, accuracy: 5)

        XCTAssertEqual(try decode(status: 2, selfDelete: "null").selfDeleteSecondsRemaining(), 0)
        XCTAssertEqual(try decode(status: 2, selfDelete: "0").selfDeleteSecondsRemaining(), 0)
        XCTAssertEqual(try decode(status: 2, selfDelete: nil).selfDeleteSecondsRemaining(), 0)
    }

    func testWindowCountsDownFromFetchTime() throws {
        let job = try decode(status: 2, selfDelete: "3600")
        let later = Date().addingTimeInterval(3_000)
        XCTAssertEqual(job.selfDeleteSecondsRemaining(at: later), 600, accuracy: 5)
        XCTAssertEqual(job.selfDeleteSecondsRemaining(at: Date().addingTimeInterval(4_000)), 0)
    }

    func testRemovedStatusIsNotAFailure() throws {
        XCTAssertEqual(try decode(status: -1, selfDelete: nil).status, .removed)
        XCTAssertEqual(try decode(status: -10, selfDelete: nil).status, .removed)
        XCTAssertFalse(POTAJobStatus.removed.isFailure)
        XCTAssertEqual(try decode(status: 55, selfDelete: nil).status, .error)
    }

    func testPlanRemovesJobsStillInWindow() throws {
        let completed = try decode(jobId: 7, status: 2, selfDelete: "7200")
        let failed = try decode(jobId: 8, status: 3, selfDelete: "600")
        let removed = try decode(jobId: 9, status: -1, selfDelete: "600")
        let plan = POTAUploadReplacePlan(jobs: [completed, failed, removed])
        XCTAssertTrue(plan.canReplace)
        XCTAssertFalse(plan.isWindowExpired)
        XCTAssertEqual(Set(plan.removeJobIds), [7, 8])
        XCTAssertEqual(plan.secondsLeft, 600, accuracy: 5)
    }

    func testPlanBlockedOnceWindowCloses() throws {
        let completed = try decode(jobId: 7, status: 2, selfDelete: "0")
        let plan = POTAUploadReplacePlan(jobs: [completed])
        XCTAssertFalse(plan.canReplace)
        XCTAssertTrue(plan.isWindowExpired)

        let empty = POTAUploadReplacePlan(jobs: [])
        XCTAssertFalse(empty.canReplace)
        XCTAssertFalse(empty.isWindowExpired)
    }

    func testTimeLeftText() {
        XCTAssertEqual(POTAUploadReplacePlan.timeLeftText(30), "under a minute")
        XCTAssertEqual(POTAUploadReplacePlan.timeLeftText(42 * 60), "42m")
        XCTAssertEqual(POTAUploadReplacePlan.timeLeftText(5 * 3_600 + 12 * 60), "5h 12m")
    }

    // MARK: Private

    private func decode(jobId: Int = 42, status: Int, selfDelete: String?) throws -> POTAJob {
        let window = selfDelete.map { ", \"selfDeleteSecondsRemaining\": \($0)" } ?? ""
        let json = """
        {"jobId": \(jobId), "status": \(status), "submitted": "2026-11-14T17:06:41",
         "reference": "US-0189", "total": 12, "inserted": 12\(window)}
        """
        return try JSONDecoder().decode(POTAJob.self, from: Data(json.utf8))
    }
}
