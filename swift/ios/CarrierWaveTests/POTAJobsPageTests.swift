import XCTest
@testable import CarrierWave

/// `/user/jobs` answers with a bare array on the legacy POTA backend and with
/// `{count, pending, entries}` on the rebuilt site (October 2026).
final class POTAJobsPageTests: XCTestCase {
    // MARK: Internal

    func testDecodesLegacyArray() throws {
        let data = Data("[\(job), \(job)]".utf8)
        let page = try JSONDecoder().decode(POTAJobsPage.self, from: data)
        XCTAssertTrue(page.isLegacyArray)
        XCTAssertEqual(page.count, 2)
        XCTAssertEqual(page.entries.count, 2)
        XCTAssertEqual(page.entries.first?.jobId, 42)
        XCTAssertEqual(page.entries.first?.status, .completed)
    }

    func testDecodesPaginatedObject() throws {
        let data = Data("{\"count\": 250, \"pending\": 3, \"entries\": [\(job)]}".utf8)
        let page = try JSONDecoder().decode(POTAJobsPage.self, from: data)
        XCTAssertFalse(page.isLegacyArray)
        XCTAssertEqual(page.count, 250)
        XCTAssertEqual(page.entries.count, 1)
        XCTAssertEqual(page.entries.first?.insertedQsos, 12)
    }

    func testPaginatedObjectWithoutCountFallsBackToEntries() throws {
        let data = Data("{\"entries\": [\(job)]}".utf8)
        let page = try JSONDecoder().decode(POTAJobsPage.self, from: data)
        XCTAssertFalse(page.isLegacyArray)
        XCTAssertEqual(page.count, 1)
    }

    func testEmptyLegacyArray() throws {
        let page = try JSONDecoder().decode(POTAJobsPage.self, from: Data("[]".utf8))
        XCTAssertTrue(page.isLegacyArray)
        XCTAssertEqual(page.count, 0)
        XCTAssertTrue(page.entries.isEmpty)
    }

    // MARK: Private

    private let job = """
    {"jobId": 42, "status": 2, "submitted": "2026-10-20T17:06:41", "processed": "2026-10-20T17:07:02",
     "reference": "US-0189", "parkName": "Don Edwards San Francisco Bay", "location": "US-CA",
     "total": 12, "inserted": 12, "callsignUsed": "N3JSV", "userComment": null}
    """
}
