//
//  QuickEntryParserTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("Quick Entry Parser Tests")
struct QuickEntryParserTests {
    // MARK: - Callsign Detection

    @Test("Single callsign returns nil")
    func singleCallsignReturnsNil() {
        // Single callsign without additional tokens is not quick entry
        let result = QuickEntryParser.parse("W1AW")
        #expect(result == nil)
    }

    @Test("Callsign with space but no tokens returns nil")
    func callsignWithSpaceButNoTokensReturnsNil() {
        let result = QuickEntryParser.parse("W1AW ")
        #expect(result == nil)
    }

    @Test("Valid callsign patterns")
    func validCallsignPatterns() {
        // Various valid callsign formats should be recognized
        #expect(QuickEntryParser.isCallsign("W1AW"))
        #expect(QuickEntryParser.isCallsign("K3LR"))
        #expect(QuickEntryParser.isCallsign("VE3ABC"))
        #expect(QuickEntryParser.isCallsign("JA1ABC"))
        #expect(QuickEntryParser.isCallsign("G4ABC"))
        #expect(QuickEntryParser.isCallsign("DL1ABC"))
        #expect(QuickEntryParser.isCallsign("9A1A"))
        #expect(QuickEntryParser.isCallsign("3DA0ABC"))
    }

    @Test("Callsign with modifiers")
    func callsignWithModifiers() {
        #expect(QuickEntryParser.isCallsign("W1AW/P"))
        #expect(QuickEntryParser.isCallsign("W1AW/M"))
        #expect(QuickEntryParser.isCallsign("I/W1AW"))
        #expect(QuickEntryParser.isCallsign("VE3/K1ABC"))
        #expect(QuickEntryParser.isCallsign("W1AW/MM"))
    }

    @Test("Invalid callsign patterns")
    func invalidCallsignPatterns() {
        #expect(!QuickEntryParser.isCallsign("599"))
        #expect(!QuickEntryParser.isCallsign("WA"))
        #expect(!QuickEntryParser.isCallsign("FREQ"))
        #expect(!QuickEntryParser.isCallsign("US-0189"))
        #expect(!QuickEntryParser.isCallsign("CN87"))
    }

    @Test("Command as first token returns nil")
    func commandAsFirstTokenReturnsNil() {
        // Commands should not trigger quick entry
        let isCommand: (String) -> Bool = { token in
            ["FREQ", "MODE", "SPOT"].contains(token)
        }
        #expect(QuickEntryParser.parse("FREQ 14.060", isCommand: isCommand) == nil)
        #expect(QuickEntryParser.parse("MODE CW", isCommand: isCommand) == nil)
        #expect(QuickEntryParser.parse("SPOT", isCommand: isCommand) == nil)
    }

    // MARK: - RST Detection

    @Test("Single RST applied to received")
    func singleRSTAppliedToReceived() {
        let result = QuickEntryParser.parse("W1AW 579")
        #expect(result != nil)
        #expect(result?.callsign == "W1AW")
        #expect(result?.rstSent == nil)
        #expect(result?.rstReceived == "579")
    }

    @Test("Two RSTs applied to sent and received")
    func twoRSTsAppliedToSentAndReceived() {
        let result = QuickEntryParser.parse("W1AW 559 579")
        #expect(result != nil)
        #expect(result?.rstSent == "559")
        #expect(result?.rstReceived == "579")
    }

    @Test("Phone RST")
    func phoneRST() {
        let result = QuickEntryParser.parse("W1AW 57")
        #expect(result != nil)
        #expect(result?.rstReceived == "57")
    }

    @Test("Valid RST patterns")
    func validRSTPatterns() {
        #expect(QuickEntryParser.isRST("599"))
        #expect(QuickEntryParser.isRST("579"))
        #expect(QuickEntryParser.isRST("339"))
        #expect(QuickEntryParser.isRST("59"))
        #expect(QuickEntryParser.isRST("57"))
        #expect(QuickEntryParser.isRST("44"))
        #expect(QuickEntryParser.isRST("11"))
    }

    @Test("Invalid RST patterns")
    func invalidRSTPatterns() {
        #expect(!QuickEntryParser.isRST("999")) // R can't be 9
        #expect(!QuickEntryParser.isRST("69")) // R can't be 6
        #expect(!QuickEntryParser.isRST("50")) // S can't be 0
        #expect(!QuickEntryParser.isRST("5")) // Too short
        #expect(!QuickEntryParser.isRST("5999")) // Too long
        #expect(!QuickEntryParser.isRST("WA")) // Not a number
    }

    // MARK: - Park Reference Detection

    @Test("Park reference detection")
    func parkReferenceDetection() {
        let result = QuickEntryParser.parse("W1AW US-0189")
        #expect(result != nil)
        #expect(result?.theirPark == "US-0189")
    }

    @Test("Park reference with other tokens")
    func parkReferenceWithOtherTokens() {
        let result = QuickEntryParser.parse("W1AW 579 US-0189")
        #expect(result != nil)
        #expect(result?.rstReceived == "579")
        #expect(result?.theirPark == "US-0189")
    }

    @Test("Valid park patterns")
    func validParkPatterns() {
        #expect(QuickEntryParser.isParkReference("US-0189"))
        #expect(QuickEntryParser.isParkReference("K-1234"))
        #expect(QuickEntryParser.isParkReference("VE-0001"))
        #expect(QuickEntryParser.isParkReference("G-0001"))
        #expect(QuickEntryParser.isParkReference("DL-0001"))
        #expect(QuickEntryParser.isParkReference("JA-12345"))
    }

    @Test("Invalid park patterns")
    func invalidParkPatterns() {
        #expect(!QuickEntryParser.isParkReference("US0189")) // Missing dash
        #expect(!QuickEntryParser.isParkReference("US-01")) // Too short
        #expect(!QuickEntryParser.isParkReference("USA-0189")) // Prefix too long
        #expect(!QuickEntryParser.isParkReference("W1AW")) // Callsign
        #expect(!QuickEntryParser.isParkReference("579")) // RST
    }

    // MARK: - Grid Square Detection

    @Test("Grid square detection")
    func gridSquareDetection() {
        let result = QuickEntryParser.parse("W1AW CN87")
        #expect(result != nil)
        #expect(result?.theirGrid == "CN87")
    }

    @Test("Six char grid square")
    func sixCharGridSquare() {
        let result = QuickEntryParser.parse("W1AW FN31pr")
        #expect(result != nil)
        #expect(result?.theirGrid == "FN31PR")
    }

    @Test("Valid grid patterns")
    func validGridPatterns() {
        #expect(QuickEntryParser.isGridSquare("CN87"))
        #expect(QuickEntryParser.isGridSquare("FN31"))
        #expect(QuickEntryParser.isGridSquare("JO22"))
        #expect(QuickEntryParser.isGridSquare("AA00"))
        #expect(QuickEntryParser.isGridSquare("RR99"))
        #expect(QuickEntryParser.isGridSquare("FN31pr"))
        #expect(QuickEntryParser.isGridSquare("CN87wk"))
    }

    @Test("Invalid grid patterns")
    func invalidGridPatterns() {
        #expect(!QuickEntryParser.isGridSquare("CN8")) // Too short
        #expect(!QuickEntryParser.isGridSquare("CN877")) // 5 chars invalid
        #expect(!QuickEntryParser.isGridSquare("SN87")) // S > R
        #expect(!QuickEntryParser.isGridSquare("1N87")) // Starts with number
        #expect(!QuickEntryParser.isGridSquare("W1AW")) // Callsign
        #expect(!QuickEntryParser.isGridSquare("WA")) // State code
    }

    // MARK: - State/Region Detection

    @Test("US state detection")
    func usStateDetection() {
        let result = QuickEntryParser.parse("W1AW WA")
        #expect(result != nil)
        #expect(result?.state == "WA")
    }

    @Test("Canadian province detection")
    func canadianProvinceDetection() {
        let result = QuickEntryParser.parse("VE3ABC ON")
        #expect(result != nil)
        #expect(result?.state == "ON")
    }

    @Test("DX region detection")
    func dxRegionDetection() {
        let result = QuickEntryParser.parse("DL1ABC DL")
        #expect(result != nil)
        #expect(result?.state == "DL")
    }

    @Test("Valid state patterns")
    func validStatePatterns() {
        // US States
        #expect(QuickEntryParser.isStateOrRegion("WA"))
        #expect(QuickEntryParser.isStateOrRegion("CA"))
        #expect(QuickEntryParser.isStateOrRegion("TX"))
        #expect(QuickEntryParser.isStateOrRegion("NY"))
        #expect(QuickEntryParser.isStateOrRegion("DC"))

        // Canadian Provinces
        #expect(QuickEntryParser.isStateOrRegion("ON"))
        #expect(QuickEntryParser.isStateOrRegion("BC"))
        #expect(QuickEntryParser.isStateOrRegion("QC"))
        #expect(QuickEntryParser.isStateOrRegion("AB"))

        // DX Regions
        #expect(QuickEntryParser.isStateOrRegion("DL"))
        #expect(QuickEntryParser.isStateOrRegion("EA"))
        #expect(QuickEntryParser.isStateOrRegion("JA"))
        #expect(QuickEntryParser.isStateOrRegion("VK"))
        #expect(QuickEntryParser.isStateOrRegion("ZL"))
    }

    @Test("Invalid state patterns")
    func invalidStatePatterns() {
        #expect(!QuickEntryParser.isStateOrRegion("XX")) // Not a real code
        #expect(!QuickEntryParser.isStateOrRegion("W1")) // Callsign prefix
        #expect(!QuickEntryParser.isStateOrRegion("599")) // RST
        #expect(!QuickEntryParser.isStateOrRegion("USA")) // Too long
    }

    // MARK: - Frequency Detection

    @Test("Frequency with decimal detected")
    func frequencyWithDecimalDetected() {
        let result = QuickEntryParser.parse("W1AW 14.060")
        #expect(result != nil)
        #expect(result?.callsign == "W1AW")
        #expect(result?.frequency == 14.060)
        #expect(result?.band == "20m")
    }

    @Test("Frequency in kHz detected")
    func frequencyInKHzDetected() {
        let result = QuickEntryParser.parse("W1AW 7030")
        #expect(result != nil)
        #expect(result?.frequency == 7.030)
        #expect(result?.band == "40m")
    }

    @Test("Frequency with RST and park")
    func frequencyWithRSTAndPark() {
        let result = QuickEntryParser.parse("K3LR 14.060 599 US-0189")
        #expect(result != nil)
        #expect(result?.callsign == "K3LR")
        #expect(result?.frequency == 14.060)
        #expect(result?.band == "20m")
        #expect(result?.rstReceived == "599")
        #expect(result?.theirPark == "US-0189")
    }

    @Test("Frequency token displayed with MHz suffix")
    func frequencyTokenDisplayedWithMHz() {
        let tokens = QuickEntryParser.parseTokens("W1AW 14.060")
        #expect(tokens.count == 3) // callsign + freq + band
        #expect(tokens[0].type == .callsign)
        #expect(tokens[1].type == .frequency)
        #expect(tokens[1].text == "14.060 MHz")
        #expect(tokens[2].type == .band)
        #expect(tokens[2].text == "20m")
    }

    @Test("Frequency without recognized band omits band token")
    func frequencyWithoutBandOmitsBandToken() {
        // 450 MHz is just outside 70cm (420-450), but 440 is in range
        let tokens = QuickEntryParser.parseTokens("W1AW 440.000")
        #expect(tokens.count == 3) // callsign + freq + band
        #expect(tokens[1].type == .frequency)
        #expect(tokens[2].type == .band)
        #expect(tokens[2].text == "70cm")
    }

    @Test("RST not confused with frequency")
    func rstNotConfusedWithFrequency() {
        // "599" should be RST, not frequency
        let result = QuickEntryParser.parse("W1AW 599")
        #expect(result?.rstReceived == "599")
        #expect(result?.frequency == nil)
    }

    // MARK: - Edge Cases

    @Test("Empty string returns nil")
    func emptyStringReturnsNil() {
        let result = QuickEntryParser.parse("")
        #expect(result == nil)
    }

    @Test("Whitespace only returns nil")
    func whitespaceOnlyReturnsNil() {
        let result = QuickEntryParser.parse("   ")
        #expect(result == nil)
    }

    @Test("Lowercase callsign normalized")
    func lowercaseCallsignNormalized() {
        let result = QuickEntryParser.parse("w1aw 59")
        #expect(result != nil)
        #expect(result?.callsign == "W1AW")
        #expect(result?.rstReceived == "59")
    }

    @Test("Three RST values treats third as notes")
    func threeRSTValuesTreatsThirdAsNotes() {
        let result = QuickEntryParser.parse("W1AW 559 579 599")
        #expect(result != nil)
        #expect(result?.rstSent == "559")
        #expect(result?.rstReceived == "579")
        #expect(result?.notes == "599")
    }

    @Test("Second callsign becomes notes")
    func secondCallsignBecomesNotes() {
        let result = QuickEntryParser.parse("W1AW K3LR 59")
        #expect(result != nil)
        #expect(result?.callsign == "W1AW")
        #expect(result?.rstReceived == "59")
        #expect(result?.notes == "K3LR")
    }
}
