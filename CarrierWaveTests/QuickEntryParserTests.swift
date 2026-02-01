//
//  QuickEntryParserTests.swift
//  CarrierWaveTests
//

import XCTest
@testable import CarrierWave

@MainActor
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

    // MARK: - Park Reference Detection

    func testParkReferenceDetection() {
        let result = QuickEntryParser.parse("W1AW US-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.theirPark, "US-0189")
    }

    func testParkReferenceWithOtherTokens() {
        let result = QuickEntryParser.parse("W1AW 579 US-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.theirPark, "US-0189")
    }

    func testValidParkPatterns() {
        XCTAssertTrue(QuickEntryParser.isParkReference("US-0189"))
        XCTAssertTrue(QuickEntryParser.isParkReference("K-1234"))
        XCTAssertTrue(QuickEntryParser.isParkReference("VE-0001"))
        XCTAssertTrue(QuickEntryParser.isParkReference("G-0001"))
        XCTAssertTrue(QuickEntryParser.isParkReference("DL-0001"))
        XCTAssertTrue(QuickEntryParser.isParkReference("JA-12345"))
    }

    func testInvalidParkPatterns() {
        XCTAssertFalse(QuickEntryParser.isParkReference("US0189")) // Missing dash
        XCTAssertFalse(QuickEntryParser.isParkReference("US-01")) // Too short
        XCTAssertFalse(QuickEntryParser.isParkReference("USA-0189")) // Prefix too long
        XCTAssertFalse(QuickEntryParser.isParkReference("W1AW")) // Callsign
        XCTAssertFalse(QuickEntryParser.isParkReference("579")) // RST
    }

    // MARK: - Grid Square Detection

    func testGridSquareDetection() {
        let result = QuickEntryParser.parse("W1AW CN87")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.theirGrid, "CN87")
    }

    func testSixCharGridSquare() {
        let result = QuickEntryParser.parse("W1AW FN31pr")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.theirGrid, "FN31PR")
    }

    func testValidGridPatterns() {
        XCTAssertTrue(QuickEntryParser.isGridSquare("CN87"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("FN31"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("JO22"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("AA00"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("RR99"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("FN31pr"))
        XCTAssertTrue(QuickEntryParser.isGridSquare("CN87wk"))
    }

    func testInvalidGridPatterns() {
        XCTAssertFalse(QuickEntryParser.isGridSquare("CN8")) // Too short
        XCTAssertFalse(QuickEntryParser.isGridSquare("CN877")) // 5 chars invalid
        XCTAssertFalse(QuickEntryParser.isGridSquare("SN87")) // S > R
        XCTAssertFalse(QuickEntryParser.isGridSquare("1N87")) // Starts with number
        XCTAssertFalse(QuickEntryParser.isGridSquare("W1AW")) // Callsign
        XCTAssertFalse(QuickEntryParser.isGridSquare("WA")) // State code
    }

    // MARK: - State/Region Detection

    func testUSStateDetection() {
        let result = QuickEntryParser.parse("W1AW WA")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.state, "WA")
    }

    func testCanadianProvinceDetection() {
        let result = QuickEntryParser.parse("VE3ABC ON")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.state, "ON")
    }

    func testDXRegionDetection() {
        let result = QuickEntryParser.parse("DL1ABC DL")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.state, "DL")
    }

    func testValidStatePatterns() {
        // US States
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("WA"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("CA"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("TX"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("NY"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("DC"))

        // Canadian Provinces
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("ON"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("BC"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("QC"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("AB"))

        // DX Regions
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("DL"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("EA"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("JA"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("VK"))
        XCTAssertTrue(QuickEntryParser.isStateOrRegion("ZL"))
    }

    func testInvalidStatePatterns() {
        XCTAssertFalse(QuickEntryParser.isStateOrRegion("XX")) // Not a real code
        XCTAssertFalse(QuickEntryParser.isStateOrRegion("W1")) // Callsign prefix
        XCTAssertFalse(QuickEntryParser.isStateOrRegion("599")) // RST
        XCTAssertFalse(QuickEntryParser.isStateOrRegion("USA")) // Too long
    }

    // MARK: - Integration Tests

    func testFullEntryWithAllFields() {
        // Full entry: "AJ7CM 579 WA US-0189" should parse all fields correctly
        let result = QuickEntryParser.parse("AJ7CM 579 WA US-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "AJ7CM")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.state, "WA")
        XCTAssertEqual(result?.theirPark, "US-0189")
        XCTAssertNil(result?.rstSent)
        XCTAssertNil(result?.theirGrid)
        XCTAssertNil(result?.notes)
    }

    func testCallsignWithRSTGridAndNotes() {
        // With grid: "W1AW 59 CN87 notes here" should capture callsign, RST, grid, and notes
        let result = QuickEntryParser.parse("W1AW 59 CN87 notes here")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "59")
        XCTAssertEqual(result?.theirGrid, "CN87")
        XCTAssertEqual(result?.notes, "NOTES HERE")
    }

    func testOrderIndependenceRSTBeforePark() {
        // Order independence: "W1AW 579 US-0189" should work
        let result = QuickEntryParser.parse("W1AW 579 US-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.theirPark, "US-0189")
    }

    func testOrderIndependenceParkBeforeRST() {
        // Order independence: "W1AW US-0189 579" should work same as above
        let result = QuickEntryParser.parse("W1AW US-0189 579")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.theirPark, "US-0189")
    }

    func testMultipleUnrecognizedTokensBecomeNotes() {
        // Multiple unrecognized tokens become notes: "W1AW 59 hello world" → notes = "HELLO WORLD"
        let result = QuickEntryParser.parse("W1AW 59 hello world")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "59")
        XCTAssertEqual(result?.notes, "HELLO WORLD")
    }

    func testP2PScenarioWithSentReceivedParkStateAndNotes() {
        // P2P scenario: "K3LR 599 599 US-1234 PA working from home"
        // → sent, received, park, state, notes
        let result = QuickEntryParser.parse("K3LR 599 599 US-1234 PA working from home")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "K3LR")
        XCTAssertEqual(result?.rstSent, "599")
        XCTAssertEqual(result?.rstReceived, "599")
        XCTAssertEqual(result?.theirPark, "US-1234")
        XCTAssertEqual(result?.state, "PA")
        XCTAssertEqual(result?.notes, "WORKING FROM HOME")
    }

    func testGridWithStateAndNotes() {
        // Grid with state and notes
        let result = QuickEntryParser.parse("VE3ABC 59 FN03 ON great signal")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "VE3ABC")
        XCTAssertEqual(result?.rstReceived, "59")
        XCTAssertEqual(result?.theirGrid, "FN03")
        XCTAssertEqual(result?.state, "ON")
        XCTAssertEqual(result?.notes, "GREAT SIGNAL")
    }

    func testAllFieldsPopulated() {
        // Maximum complexity: callsign, sent RST, received RST, park, state, grid, notes
        let result = QuickEntryParser.parse("W1AW 559 579 US-0001 CT FN31 testing all fields")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstSent, "559")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.theirPark, "US-0001")
        XCTAssertEqual(result?.state, "CT")
        XCTAssertEqual(result?.theirGrid, "FN31")
        XCTAssertEqual(result?.notes, "TESTING ALL FIELDS")
    }

    func testNotesWithMixedCase() {
        // Notes should be uppercased
        let result = QuickEntryParser.parse("W1AW 59 Hello World")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.notes, "HELLO WORLD")
    }

    func testSingleUnrecognizedTokenBecomesNotes() {
        let result = QuickEntryParser.parse("W1AW 59 portable")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "59")
        XCTAssertEqual(result?.notes, "PORTABLE")
    }

    func testNoNotesWhenAllTokensRecognized() {
        let result = QuickEntryParser.parse("W1AW 579 US-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.theirPark, "US-0189")
        XCTAssertNil(result?.notes)
    }
}
