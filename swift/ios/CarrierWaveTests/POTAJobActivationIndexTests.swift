import XCTest
@testable import CarrierWave

/// Jobs are attached to activations for the POTA Jobs section. A job POTA has
/// not processed yet reports no first QSO, and must still show on its session.
@MainActor
final class POTAJobActivationIndexTests: XCTestCase {
    // MARK: Internal

    func testProcessedJobMatchesByDate() {
        let activation = makeActivation(daysAgo: 30)
        let other = makeActivation(daysAgo: 10)
        let job = makeJob(jobId: 1, firstQSO: activation.utcDate.addingTimeInterval(3_600))

        let index = POTAJob.indexByActivation(jobs: [job], activations: [activation, other])
        XCTAssertEqual(index[activation.id]?.map(\.jobId), [1])
        XCTAssertNil(index[other.id])
    }

    func testUnprocessedJobShowsOnNewestUnmatchedActivation() {
        let older = makeActivation(daysAgo: 30)
        let newer = makeActivation(daysAgo: 10)
        let queued = makeJob(jobId: 2, status: .pending, firstQSO: nil)

        let index = POTAJob.indexByActivation(jobs: [queued], activations: [older, newer])
        XCTAssertEqual(index[newer.id]?.map(\.jobId), [2])
        XCTAssertNil(index[older.id])
    }

    func testUnprocessedJobSkipsActivationsThatAlreadyHaveAJob() {
        let older = makeActivation(daysAgo: 30)
        let newer = makeActivation(daysAgo: 10)
        let done = makeJob(jobId: 1, firstQSO: newer.utcDate.addingTimeInterval(60))
        let queued = makeJob(jobId: 2, status: .pending, firstQSO: nil)

        let index = POTAJob.indexByActivation(jobs: [done, queued], activations: [older, newer])
        XCTAssertEqual(index[newer.id]?.map(\.jobId), [1])
        XCTAssertEqual(index[older.id]?.map(\.jobId), [2])
    }

    func testOtherParkIsNotMatched() {
        let activation = makeActivation(daysAgo: 10)
        let queued = makeJob(jobId: 3, status: .pending, reference: "US-4567", firstQSO: nil)

        let index = POTAJob.indexByActivation(jobs: [queued], activations: [activation])
        XCTAssertTrue(index.isEmpty)
    }

    // MARK: Private

    private let now = Date()

    private func makeActivation(daysAgo: Int) -> POTAActivation {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let day = calendar.startOfDay(for: now.addingTimeInterval(-Double(daysAgo) * 86_400))
        return POTAActivation(parkReference: "US-0189", utcDate: day, callsign: "W6JSV", qsos: [])
    }

    private func makeJob(
        jobId: Int, status: POTAJobStatus = .completed, reference: String = "US-0189",
        firstQSO: Date?
    ) -> POTAJob {
        POTAJob(
            jobId: jobId, status: status, submitted: now, processed: nil,
            reference: reference, parkName: nil, location: nil,
            totalQsos: 10, insertedQsos: 0, callsignUsed: "w6jsv", userComment: nil,
            firstQSO: firstQSO
        )
    }
}
