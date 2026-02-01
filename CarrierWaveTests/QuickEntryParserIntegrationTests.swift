//
//  QuickEntryParserIntegrationTests.swift
//  CarrierWaveTests
//

import XCTest
@testable import CarrierWave

@MainActor
final class QuickEntryParserIntegrationTests: XCTestCase {
    // MARK: - Integration Tests

    func testFullEntryWithAllFields() {
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
        let result = QuickEntryParser.parse("W1AW 59 CN87 notes here")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "59")
        XCTAssertEqual(result?.theirGrid, "CN87")
        XCTAssertEqual(result?.notes, "NOTES HERE")
    }

    func testOrderIndependenceRSTBeforePark() {
        let result = QuickEntryParser.parse("W1AW 579 US-0189")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.theirPark, "US-0189")
    }

    func testOrderIndependenceParkBeforeRST() {
        let result = QuickEntryParser.parse("W1AW US-0189 579")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "579")
        XCTAssertEqual(result?.theirPark, "US-0189")
    }

    func testMultipleUnrecognizedTokensBecomeNotes() {
        let result = QuickEntryParser.parse("W1AW 59 hello world")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "W1AW")
        XCTAssertEqual(result?.rstReceived, "59")
        XCTAssertEqual(result?.notes, "HELLO WORLD")
    }

    func testP2PScenarioWithSentReceivedParkStateAndNotes() {
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
        let result = QuickEntryParser.parse("VE3ABC 59 FN03 ON great signal")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.callsign, "VE3ABC")
        XCTAssertEqual(result?.rstReceived, "59")
        XCTAssertEqual(result?.theirGrid, "FN03")
        XCTAssertEqual(result?.state, "ON")
        XCTAssertEqual(result?.notes, "GREAT SIGNAL")
    }

    func testAllFieldsPopulated() {
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

    // MARK: - Parsed Tokens

    func testParsedTokensReturnsColorCodingInfo() {
        let tokens = QuickEntryParser.parseTokens("W1AW 579 WA US-0189")
        XCTAssertEqual(tokens.count, 4)

        XCTAssertEqual(tokens[0].text, "W1AW")
        XCTAssertEqual(tokens[0].type, .callsign)

        XCTAssertEqual(tokens[1].text, "579")
        XCTAssertEqual(tokens[1].type, .rstReceived)

        XCTAssertEqual(tokens[2].text, "WA")
        XCTAssertEqual(tokens[2].type, .state)

        XCTAssertEqual(tokens[3].text, "US-0189")
        XCTAssertEqual(tokens[3].type, .park)
    }

    func testParsedTokensWithNotes() {
        let tokens = QuickEntryParser.parseTokens("W1AW 59 hello world")
        XCTAssertEqual(tokens.count, 4)

        XCTAssertEqual(tokens[0].text, "W1AW")
        XCTAssertEqual(tokens[0].type, .callsign)

        XCTAssertEqual(tokens[1].text, "59")
        XCTAssertEqual(tokens[1].type, .rstReceived)

        XCTAssertEqual(tokens[2].text, "HELLO")
        XCTAssertEqual(tokens[2].type, .notes)

        XCTAssertEqual(tokens[3].text, "WORLD")
        XCTAssertEqual(tokens[3].type, .notes)
    }

    func testParsedTokensWithDualRST() {
        let tokens = QuickEntryParser.parseTokens("W1AW 559 579")
        XCTAssertEqual(tokens.count, 3)

        XCTAssertEqual(tokens[0].text, "W1AW")
        XCTAssertEqual(tokens[0].type, .callsign)

        XCTAssertEqual(tokens[1].text, "559")
        XCTAssertEqual(tokens[1].type, .rstSent)

        XCTAssertEqual(tokens[2].text, "579")
        XCTAssertEqual(tokens[2].type, .rstReceived)
    }

    func testParsedTokensEmptyForSingleToken() {
        let tokens = QuickEntryParser.parseTokens("W1AW")
        XCTAssertTrue(tokens.isEmpty)
    }

    func testParsedTokensEmptyForCommand() {
        let tokens = QuickEntryParser.parseTokens("FREQ 14.060")
        XCTAssertTrue(tokens.isEmpty)
    }

    func testParsedTokensWithGrid() {
        let tokens = QuickEntryParser.parseTokens("W1AW 59 CN87")
        XCTAssertEqual(tokens.count, 3)

        XCTAssertEqual(tokens[0].text, "W1AW")
        XCTAssertEqual(tokens[0].type, .callsign)

        XCTAssertEqual(tokens[1].text, "59")
        XCTAssertEqual(tokens[1].type, .rstReceived)

        XCTAssertEqual(tokens[2].text, "CN87")
        XCTAssertEqual(tokens[2].type, .grid)
    }
}
