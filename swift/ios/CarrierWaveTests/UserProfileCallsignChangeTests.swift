import CarrierWaveData
import XCTest
@testable import CarrierWave

// MARK: - UserProfileCallsignChangeTests

/// CAR-349 regression: a callsign change must survive relaunch even while a
/// connected service (the QRZ Logbook API key) still reports the old callsign.
///
/// Exercises the real Keychain-backed stores. Each test starts from an empty
/// callsign state and the previous state is restored afterwards.
@MainActor
final class UserProfileCallsignChangeTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        snapshot = CallsignStoreSnapshot.capture()
        CallsignStoreSnapshot.clear()
    }

    override func tearDown() async throws {
        snapshot?.restore()
        snapshot = nil
        try await super.tearDown()
    }

    /// Change → "relaunch" (store reconcile + QRZ sync reporting the old key
    /// callsign) → the new callsign must remain in every store.
    func testDetectedOldCallsignDoesNotRevertAfterExplicitChange() throws {
        try profileService.saveProfile(UserProfile(callsign: "W1OLD"))

        let replaced = try profileService.applyCallsignChangeIfNeeded(newCallsign: "W1NEW")
        XCTAssertEqual(replaced, "W1OLD")
        assertAllStores(are: "W1NEW")
        XCTAssertTrue(aliasService.getPreviousCallsigns().contains("W1OLD"))

        // Relaunch: scenePhase → .active reconciles the derived caches …
        profileService.reconcileCallsignStores()
        assertAllStores(are: "W1NEW")

        // … and the QRZ sync validates the API key, which still belongs to the
        // old callsign. That must not flip the profile back.
        let detected = try profileService.applyDetectedCallsignChangeIfNeeded(newCallsign: "W1OLD")
        XCTAssertNil(detected)
        assertAllStores(are: "W1NEW")

        profileService.reconcileCallsignStores()
        assertAllStores(are: "W1NEW")
        XCTAssertEqual(profileService.getProfile()?.callsign, "W1NEW")
    }

    /// A detected callsign the operator never retired is still applied, so a
    /// key for a genuinely new call keeps working the way it always has.
    func testDetectedNewCallsignStillApplies() throws {
        try profileService.saveProfile(UserProfile(callsign: "W1OLD"))

        let replaced = try profileService.applyDetectedCallsignChangeIfNeeded(newCallsign: "W1QRZ")
        XCTAssertEqual(replaced, "W1OLD")
        assertAllStores(are: "W1QRZ")
    }

    /// Deliberately switching back to a retired callsign makes it current
    /// again, so it must leave the previous list (otherwise the detected-
    /// callsign guard would treat the operator's real call as stale).
    func testExplicitSwitchBackRemovesCallsignFromPreviousList() throws {
        try profileService.saveProfile(UserProfile(callsign: "W1OLD"))
        try profileService.applyCallsignChangeIfNeeded(newCallsign: "W1NEW")
        try profileService.applyCallsignChangeIfNeeded(newCallsign: "W1OLD")

        assertAllStores(are: "W1OLD")
        let previous = aliasService.getPreviousCallsigns()
        XCTAssertTrue(previous.contains("W1NEW"))
        XCTAssertFalse(previous.contains("W1OLD"))

        // And a QRZ key for the interim call no longer wins either.
        XCTAssertNil(try profileService.applyDetectedCallsignChangeIfNeeded(newCallsign: "W1NEW"))
        assertAllStores(are: "W1OLD")
    }

    // MARK: Private

    private let profileService = UserProfileService.shared
    private let aliasService = CallsignAliasService.shared
    private var snapshot: CallsignStoreSnapshot?

    private func assertAllStores(
        are callsign: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(profileService.getProfile()?.callsign, callsign, "profile", file: file, line: line)
        XCTAssertEqual(aliasService.getCurrentCallsign(), callsign, "keychain", file: file, line: line)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "loggerDefaultCallsign"),
            callsign,
            "defaults",
            file: file,
            line: line
        )
    }
}

// MARK: - CallsignStoreSnapshot

/// Everything the callsign change touches, so tests can run against the real
/// stores without disturbing the developer's own configuration.
private struct CallsignStoreSnapshot {
    // MARK: Internal

    let profile: Data?
    let currentCallsign: Data?
    let previousCallsigns: Data?
    let defaultCallsign: String?
    let pendingChange: PendingCallsignChange?

    @MainActor
    static func capture() -> CallsignStoreSnapshot {
        let keychain = KeychainHelper.shared
        return CallsignStoreSnapshot(
            profile: try? keychain.read(for: KeychainHelper.Keys.userProfile),
            currentCallsign: try? keychain.read(for: KeychainHelper.Keys.currentCallsign),
            previousCallsigns: try? keychain.read(for: KeychainHelper.Keys.previousCallsigns),
            defaultCallsign: UserDefaults.standard.string(forKey: "loggerDefaultCallsign"),
            pendingChange: CallsignChangeGuide.shared.pending
        )
    }

    @MainActor
    static func clear() {
        let keychain = KeychainHelper.shared
        try? keychain.delete(for: KeychainHelper.Keys.userProfile)
        try? keychain.delete(for: KeychainHelper.Keys.currentCallsign)
        try? keychain.delete(for: KeychainHelper.Keys.previousCallsigns)
        UserDefaults.standard.removeObject(forKey: "loggerDefaultCallsign")
        CallsignChangeGuide.shared.pending = nil
    }

    @MainActor
    func restore() {
        let keychain = KeychainHelper.shared
        Self.put(profile, for: KeychainHelper.Keys.userProfile, in: keychain)
        Self.put(currentCallsign, for: KeychainHelper.Keys.currentCallsign, in: keychain)
        Self.put(previousCallsigns, for: KeychainHelper.Keys.previousCallsigns, in: keychain)
        if let defaultCallsign {
            UserDefaults.standard.set(defaultCallsign, forKey: "loggerDefaultCallsign")
        } else {
            UserDefaults.standard.removeObject(forKey: "loggerDefaultCallsign")
        }
        CallsignChangeGuide.shared.pending = pendingChange
    }

    // MARK: Private

    private static func put(_ data: Data?, for key: String, in keychain: KeychainHelper) {
        if let data {
            try? keychain.save(data, for: key)
        } else {
            try? keychain.delete(for: key)
        }
    }
}
