import Foundation
import XCTest
@testable import CarrierWaveData

// MARK: - ServerSyncPhase7Tests

/// Pure-logic coverage for the Phase 7 iOS wiring: the snapshot cadence
/// heuristic (7.4), the `CwStoreSyncMode` selection seam (7.2), and the
/// escrow-fingerprint validation that gates pushes (7.1).
final class ServerSyncPhase7Tests: XCTestCase {
    // MARK: - ServerSyncSnapshotHeuristic (7.4)

    func testSnapshotNotDueWithZeroEntries() {
        XCTAssertFalse(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 0, totalLogSize: 0)
        )
        XCTAssertFalse(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 0, totalLogSize: 10_000)
        )
    }

    func testSmallLogUsesFloorOf30() {
        // total_log * 0.2 = 10 < 30 → floor applies.
        XCTAssertFalse(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 29, totalLogSize: 50)
        )
        XCTAssertTrue(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 30, totalLogSize: 50)
        )
    }

    func testEmptyLogStillRequiresFloor() {
        XCTAssertFalse(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 29, totalLogSize: 0)
        )
        XCTAssertTrue(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 30, totalLogSize: 0)
        )
    }

    func testLargeLogUsesProportionalThreshold() {
        // total_log = 2_000 → threshold = 400.
        XCTAssertFalse(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 399, totalLogSize: 2_000)
        )
        XCTAssertTrue(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 400, totalLogSize: 2_000)
        )
    }

    func testBoundaryWhereFractionEqualsFloor() {
        // total_log = 150 → 150 * 0.2 = 30 → threshold exactly the floor.
        XCTAssertFalse(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 29, totalLogSize: 150)
        )
        XCTAssertTrue(
            ServerSyncSnapshotHeuristic.isDue(entriesSinceSnapshot: 30, totalLogSize: 150)
        )
    }

    // MARK: - CwStoreSyncMode (7.2)

    func testSyncModeDefaultsToOff() {
        let key = CwStoreSyncMode.appStorageKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(CwStoreSyncMode.current, .off)

        UserDefaults.standard.set("garbage", forKey: key)
        XCTAssertEqual(CwStoreSyncMode.current, .off, "unknown raw values fall back to .off")

        UserDefaults.standard.set("serverSync", forKey: key)
        XCTAssertEqual(CwStoreSyncMode.current, .serverSync)
    }

    func testSyncModeGating() {
        XCTAssertTrue(CwStoreSyncMode.off.startsCKSyncEngine)
        XCTAssertFalse(CwStoreSyncMode.off.drivesServerSync)
        XCTAssertFalse(CwStoreSyncMode.serverSync.startsCKSyncEngine)
        XCTAssertTrue(CwStoreSyncMode.serverSync.drivesServerSync)
    }

    // MARK: - SyncEscrowValidation (7.1)

    func testFingerprintIsStableAndDistinct() {
        let one = SyncEscrowValidation.fingerprint(wrappedKeyB64: "AAAA")
        let two = SyncEscrowValidation.fingerprint(wrappedKeyB64: "AAAA")
        let other = SyncEscrowValidation.fingerprint(wrappedKeyB64: "BBBB")
        XCTAssertEqual(one, two)
        XCTAssertNotEqual(one, other)
        XCTAssertEqual(one.count, 64, "SHA-256 hex")
    }

    func testNoServerEscrowRefusesPush() {
        // Pushing with no escrow on the server would poison the tenant with
        // blobs nothing can ever decrypt — refuse regardless of seeded state.
        XCTAssertEqual(
            SyncEscrowValidation.verdict(
                serverWrappedKeyB64: nil, localFingerprint: "abc", isSeeded: true
            ),
            .refuseNoEscrow
        )
        XCTAssertEqual(
            SyncEscrowValidation.verdict(
                serverWrappedKeyB64: nil, localFingerprint: nil, isSeeded: false
            ),
            .refuseNoEscrow
        )
    }

    func testUnvalidatedKeyOnNewServerRefusesPush() {
        // The 2026-07-03 incident shape: a local key never validated against
        // this base URL, first push pending → must refuse.
        XCTAssertEqual(
            SyncEscrowValidation.verdict(
                serverWrappedKeyB64: "blob", localFingerprint: nil, isSeeded: false
            ),
            .refuseMismatch
        )
    }

    func testLegacySeededEnrollmentAdoptsFingerprint() {
        let expected = SyncEscrowValidation.fingerprint(wrappedKeyB64: "blob")
        XCTAssertEqual(
            SyncEscrowValidation.verdict(
                serverWrappedKeyB64: "blob", localFingerprint: nil, isSeeded: true
            ),
            .adoptAndAllow(fingerprint: expected)
        )
    }

    func testMatchingFingerprintAllows() {
        let fingerprint = SyncEscrowValidation.fingerprint(wrappedKeyB64: "blob")
        XCTAssertEqual(
            SyncEscrowValidation.verdict(
                serverWrappedKeyB64: "blob", localFingerprint: fingerprint, isSeeded: false
            ),
            .allow
        )
        XCTAssertEqual(
            SyncEscrowValidation.verdict(
                serverWrappedKeyB64: "blob", localFingerprint: fingerprint, isSeeded: true
            ),
            .allow
        )
    }

    func testReplacedEscrowRefusesEvenWhenSeeded() {
        let stale = SyncEscrowValidation.fingerprint(wrappedKeyB64: "old-blob")
        XCTAssertEqual(
            SyncEscrowValidation.verdict(
                serverWrappedKeyB64: "new-blob", localFingerprint: stale, isSeeded: true
            ),
            .refuseMismatch
        )
    }
}
