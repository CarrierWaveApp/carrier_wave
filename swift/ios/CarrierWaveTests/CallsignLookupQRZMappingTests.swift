import CarrierWaveCore
import CarrierWaveData
import XCTest
@testable import CarrierWave

/// Tests for the `FfiQrzLookup` → `CallsignInfo` projection used by the QRZ
/// callbook FFI migration (Phase 0c). The FFI result doesn't carry the
/// "Looked up as …" redirect note, so it's reconstructed Swift-side from the
/// queried vs. canonical callsign — these tests pin that logic.
@MainActor
final class CallsignLookupQRZMappingTests: XCTestCase {
    // MARK: Internal

    func testMapsAllFieldsAndTagsSourceQRZ() {
        let ffi = lookup(
            callsign: "W6JY",
            name: "Jay Vana",
            firstName: "Jay",
            nickname: "Jay",
            qth: "San Francisco",
            state: "CA",
            country: "United States",
            grid: "CM87",
            licenseClass: "Extra",
            previousCallsign: "W6JSV"
        )

        let info = service.callsignInfo(from: ffi, queried: "W6JY")

        XCTAssertEqual(info.callsign, "W6JY")
        XCTAssertEqual(info.name, "Jay Vana")
        XCTAssertEqual(info.firstName, "Jay")
        XCTAssertEqual(info.nickname, "Jay")
        XCTAssertEqual(info.qth, "San Francisco")
        XCTAssertEqual(info.state, "CA")
        XCTAssertEqual(info.country, "United States")
        XCTAssertEqual(info.grid, "CM87")
        XCTAssertEqual(info.licenseClass, "Extra")
        XCTAssertEqual(info.previousCallsign, "W6JSV")
        XCTAssertEqual(info.source, .qrz)
    }

    func testNoRedirectNoteWhenQueriedMatchesCanonical() {
        let info = service.callsignInfo(from: lookup(callsign: "W6JY"), queried: "W6JY")
        XCTAssertNil(info.callsignChangeNote)
    }

    func testNoRedirectNoteWhenOnlyCaseDiffers() {
        // Queried lowercase, canonical uppercase — same callsign, no redirect.
        let info = service.callsignInfo(from: lookup(callsign: "W6JY"), queried: "w6jy")
        XCTAssertNil(info.callsignChangeNote)
        XCTAssertEqual(info.callsign, "W6JY")
    }

    func testRedirectNoteWhenCanonicalDiffers() {
        // QRZ resolved an old/alias callsign to its current holder.
        let info = service.callsignInfo(from: lookup(callsign: "W6JY"), queried: "W6JSV")
        XCTAssertEqual(info.callsignChangeNote, "Looked up as W6JSV")
        XCTAssertEqual(info.callsign, "W6JY")
    }

    func testRedirectNoteUppercasesQueriedCallsign() {
        let info = service.callsignInfo(from: lookup(callsign: "W6JY"), queried: "w6jsv")
        XCTAssertEqual(info.callsignChangeNote, "Looked up as W6JSV")
    }

    func testNilOptionalsPassThrough() {
        let info = service.callsignInfo(from: lookup(callsign: "W6JY"), queried: "W6JY")
        XCTAssertNil(info.name)
        XCTAssertNil(info.grid)
        XCTAssertNil(info.previousCallsign)
        XCTAssertEqual(info.source, .qrz)
    }

    // MARK: Private

    private let service = CallsignLookupService(modelContext: nil)

    private func lookup(
        callsign: String,
        name: String? = nil,
        firstName: String? = nil,
        nickname: String? = nil,
        qth: String? = nil,
        state: String? = nil,
        country: String? = nil,
        grid: String? = nil,
        licenseClass: String? = nil,
        previousCallsign: String? = nil
    ) -> FfiQrzLookup {
        FfiQrzLookup(
            callsign: callsign,
            name: name,
            firstName: firstName,
            nickname: nickname,
            qth: qth,
            state: state,
            country: country,
            grid: grid,
            licenseClass: licenseClass,
            previousCallsign: previousCallsign,
            lat: nil,
            lon: nil
        )
    }
}
