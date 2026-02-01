//
//  QuickEntryParserTests.swift
//  CarrierWaveTests
//

import XCTest
@testable import CarrierWave

final class QuickEntryParserTests: XCTestCase {
    // MARK: - Callsign Detection

    func testSingleCallsignReturnsNil() {
        // Single callsign without additional tokens is not quick entry
        let result = QuickEntryParser.parse("W1AW")
        XCTAssertNil(result)
    }

    func testCallsignWithSpaceButNoTokensReturnsNil() {
        let result = QuickEntryParser.parse("W1AW ")
        XCTAssertNil(result)
    }

    func testValidCallsignPatterns() {
        // Various valid callsign formats should be recognized
        XCTAssertTrue(QuickEntryParser.isCallsign("W1AW"))
        XCTAssertTrue(QuickEntryParser.isCallsign("K3LR"))
        XCTAssertTrue(QuickEntryParser.isCallsign("VE3ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("JA1ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("G4ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("DL1ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("9A1A"))
        XCTAssertTrue(QuickEntryParser.isCallsign("3DA0ABC"))
    }

    func testCallsignWithModifiers() {
        XCTAssertTrue(QuickEntryParser.isCallsign("W1AW/P"))
        XCTAssertTrue(QuickEntryParser.isCallsign("W1AW/M"))
        XCTAssertTrue(QuickEntryParser.isCallsign("I/W1AW"))
        XCTAssertTrue(QuickEntryParser.isCallsign("VE3/K1ABC"))
        XCTAssertTrue(QuickEntryParser.isCallsign("W1AW/MM"))
    }

    func testInvalidCallsignPatterns() {
        XCTAssertFalse(QuickEntryParser.isCallsign("599"))
        XCTAssertFalse(QuickEntryParser.isCallsign("WA"))
        XCTAssertFalse(QuickEntryParser.isCallsign("FREQ"))
        XCTAssertFalse(QuickEntryParser.isCallsign("US-0189"))
        XCTAssertFalse(QuickEntryParser.isCallsign("CN87"))
    }

    func testCommandAsFirstTokenReturnsNil() {
        // Commands should not trigger quick entry
        XCTAssertNil(QuickEntryParser.parse("FREQ 14.060"))
        XCTAssertNil(QuickEntryParser.parse("MODE CW"))
        XCTAssertNil(QuickEntryParser.parse("SPOT"))
    }

    // MARK: - RST Detection

    func testSingleRSTAppliedToReceived() {
        let result = QuickEntryParser.parse("W1AW 579")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertNil(result?.rstSent)
        XCTAssertEqual(result?.rstReceived, "579")
    }

    func testTwoRSTsAppliedToSentAndReceived() {
        let result = QuickEntryParser.parse("W1AW 559 579")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rstSent, "559")
        XCTAssertEqual(result?.rstReceived, "579")
    }

    func testPhoneRST() {
        let result = QuickEntryParser.parse("W1AW 57")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rstReceived, "57")
    }

    func testValidRSTPatterns() {
        XCTAssertTrue(QuickEntryParser.isRST("599"))
        XCTAssertTrue(QuickEntryParser.isRST("579"))
        XCTAssertTrue(QuickEntryParser.isRST("339"))
        XCTAssertTrue(QuickEntryParser.isRST("59"))
        XCTAssertTrue(QuickEntryParser.isRST("57"))
        XCTAssertTrue(QuickEntryParser.isRST("44"))
        XCTAssertTrue(QuickEntryParser.isRST("11"))
    }

    func testInvalidRSTPatterns() {
        XCTAssertFalse(QuickEntryParser.isRST("999")) // R can't be 9
        XCTAssertFalse(QuickEntryParser.isRST("69")) // R can't be 6
        XCTAssertFalse(QuickEntryParser.isRST("50")) // S can't be 0
        XCTAssertFalse(QuickEntryParser.isRST("5")) // Too short
        XCTAssertFalse(QuickEntryParser.isRST("5999")) // Too long
        XCTAssertFalse(QuickEntryParser.isRST("WA")) // Not a number
    }
}
