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
}
