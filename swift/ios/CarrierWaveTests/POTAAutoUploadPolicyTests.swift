import XCTest
@testable import CarrierWave

/// Sync uploads a POTA activation only once it has settled, and paces its
/// attempts so a failing upload is not retried on every sync tick.
@MainActor
final class POTAAutoUploadPolicyTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func testFinishedActivationUploads() {
        let hold = POTAAutoUploadPolicy.hold(
            newestQSO: now.addingTimeInterval(-45 * 60), inActiveSession: false, now: now
        )
        XCTAssertNil(hold)
    }

    func testActiveSessionIsHeldEvenWhenQuiet() {
        let hold = POTAAutoUploadPolicy.hold(
            newestQSO: now.addingTimeInterval(-3 * 60 * 60), inActiveSession: true, now: now
        )
        XCTAssertEqual(hold, .sessionActive)
    }

    func testRecentQSOHoldsActivation() {
        let hold = POTAAutoUploadPolicy.hold(
            newestQSO: now.addingTimeInterval(-10 * 60), inActiveSession: false, now: now
        )
        XCTAssertEqual(hold, .stillSettling)
    }

    func testOldActivationIsLeftForManualUpload() {
        let hold = POTAAutoUploadPolicy.hold(
            newestQSO: now.addingTimeInterval(-15 * 24 * 60 * 60), inActiveSession: false, now: now
        )
        XCTAssertEqual(hold, .tooOld)
    }

    func testFirstAttemptIsNotDelayed() {
        let wait = POTAAutoUploadPolicy.secondsUntilNextAttempt(
            lastAttempt: nil, consecutiveFailures: 0, now: now
        )
        XCTAssertEqual(wait, 0)
    }

    func testAttemptsAreTenMinutesApart() {
        let wait = POTAAutoUploadPolicy.secondsUntilNextAttempt(
            lastAttempt: now.addingTimeInterval(-4 * 60), consecutiveFailures: 0, now: now
        )
        XCTAssertEqual(wait, 6 * 60, accuracy: 1)

        let later = POTAAutoUploadPolicy.secondsUntilNextAttempt(
            lastAttempt: now.addingTimeInterval(-11 * 60), consecutiveFailures: 0, now: now
        )
        XCTAssertEqual(later, 0)
    }

    func testFailuresBackOffUpToSixHours() {
        XCTAssertEqual(POTAAutoUploadPolicy.waitAfterAttempt(consecutiveFailures: 1), 20 * 60)
        XCTAssertEqual(POTAAutoUploadPolicy.waitAfterAttempt(consecutiveFailures: 3), 80 * 60)
        XCTAssertEqual(POTAAutoUploadPolicy.waitAfterAttempt(consecutiveFailures: 50), 6 * 60 * 60)
    }

    func testClockMovingBackwardsDoesNotBlock() {
        let wait = POTAAutoUploadPolicy.secondsUntilNextAttempt(
            lastAttempt: now.addingTimeInterval(60 * 60), consecutiveFailures: 4, now: now
        )
        XCTAssertEqual(wait, 0)
    }

    func testThrottleCountsFailuresAndResetsOnSuccess() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let throttle = POTAAutoUploadThrottle(defaults: defaults)
        XCTAssertEqual(throttle.secondsUntilNextAttempt(now: now), 0)

        throttle.recordAttempt(failed: true, now: now)
        throttle.recordAttempt(failed: true, now: now)
        XCTAssertEqual(throttle.consecutiveFailures, 2)
        XCTAssertEqual(throttle.secondsUntilNextAttempt(now: now), 40 * 60, accuracy: 1)

        throttle.recordAttempt(failed: false, now: now)
        XCTAssertEqual(throttle.consecutiveFailures, 0)
        XCTAssertEqual(throttle.secondsUntilNextAttempt(now: now), 10 * 60, accuracy: 1)
    }

    // MARK: Private

    private let suiteName = "POTAAutoUploadPolicyTests"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
}
