//
//  FT8MessageTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("FT8 Message Tests")
struct FT8MessageTests {
    // MARK: - CQ Message Properties

    @Test("CQ message is callable and has correct properties")
    func cqMessageProperties() {
        let msg = FT8Message.cq(call: "K1ABC", grid: "FN42", modifier: nil)
        #expect(msg.isCallable == true)
        #expect(msg.callerCallsign == "K1ABC")
        #expect(msg.grid == "FN42")
        #expect(msg.cqModifier == nil)
        #expect(msg.completesQSO == false)
    }

    @Test("CQ POTA message has correct modifier")
    func cqPotaMessage() {
        let msg = FT8Message.cq(call: "K7ABC", grid: "CN87", modifier: "POTA")
        #expect(msg.isCallable == true)
        #expect(msg.cqModifier == "POTA")
        #expect(msg.callerCallsign == "K7ABC")
        #expect(msg.grid == "CN87")
    }

    // MARK: - Signal Report Properties

    @Test("Signal report is not callable and isDirectedTo works")
    func signalReportProperties() {
        let msg = FT8Message.signalReport(from: "K1ABC", to: "W9XYZ", dB: -11)
        #expect(msg.isCallable == false)
        #expect(msg.callerCallsign == "K1ABC")
        #expect(msg.isDirectedTo("W9XYZ") == true)
        #expect(msg.isDirectedTo("w9xyz") == true) // case-insensitive
        #expect(msg.isDirectedTo("K1ABC") == false)
        #expect(msg.completesQSO == false)
    }

    // MARK: - QSO Completion

    @Test("RR73 completes QSO")
    func rr73CompletesQSO() {
        let msg = FT8Message.rogerEnd(from: "K1ABC", to: "W9XYZ")
        #expect(msg.completesQSO == true)
    }

    @Test("73 completes QSO")
    func endCompletesQSO() {
        let msg = FT8Message.end(from: "K1ABC", to: "W9XYZ")
        #expect(msg.completesQSO == true)
    }

    @Test("Standard directed message does not complete QSO")
    func directedDoesNotComplete() {
        let msg = FT8Message.directed(from: "K1ABC", to: "W9XYZ", grid: "EN37")
        #expect(msg.completesQSO == false)
    }

    // MARK: - Grid and Modifier for Non-CQ Types

    @Test("Directed message has grid")
    func directedGrid() {
        let msg = FT8Message.directed(from: "K1ABC", to: "W9XYZ", grid: "EN37")
        #expect(msg.grid == "EN37")
    }

    @Test("Signal report has no grid")
    func signalReportNoGrid() {
        let msg = FT8Message.signalReport(from: "K1ABC", to: "W9XYZ", dB: -11)
        #expect(msg.grid == nil)
    }

    @Test("Non-CQ message has no modifier")
    func nonCqNoModifier() {
        let msg = FT8Message.directed(from: "K1ABC", to: "W9XYZ", grid: "EN37")
        #expect(msg.cqModifier == nil)
    }

    @Test("Free text has no caller callsign")
    func freeTextNoCallsign() {
        let msg = FT8Message.freeText("TNX BOB 73 GL")
        #expect(msg.callerCallsign == nil)
        #expect(msg.isCallable == false)
        #expect(msg.grid == nil)
    }

    // MARK: - Parse Tests

    @Test("Parse CQ K1ABC FN42")
    func parseCQ() {
        let msg = FT8Message.parse("CQ K1ABC FN42")
        #expect(msg == .cq(call: "K1ABC", grid: "FN42", modifier: nil))
    }

    @Test("Parse CQ POTA K7ABC CN87")
    func parseCQPota() {
        let msg = FT8Message.parse("CQ POTA K7ABC CN87")
        #expect(msg == .cq(call: "K7ABC", grid: "CN87", modifier: "POTA"))
    }

    @Test("Parse signal report W9XYZ K1ABC -11")
    func parseSignalReport() {
        let msg = FT8Message.parse("W9XYZ K1ABC -11")
        #expect(msg == .signalReport(from: "K1ABC", to: "W9XYZ", dB: -11))
    }

    @Test("Parse RR73 message W9XYZ K1ABC RR73")
    func parseRR73() {
        let msg = FT8Message.parse("W9XYZ K1ABC RR73")
        #expect(msg == .rogerEnd(from: "K1ABC", to: "W9XYZ"))
    }

    @Test("Parse directed with grid K1ABC W9XYZ EN37")
    func parseDirected() {
        let msg = FT8Message.parse("K1ABC W9XYZ EN37")
        #expect(msg == .directed(from: "W9XYZ", to: "K1ABC", grid: "EN37"))
    }

    @Test("Parse roger report K1ABC W9XYZ R-07")
    func parseRogerReport() {
        let msg = FT8Message.parse("K1ABC W9XYZ R-07")
        #expect(msg == .rogerReport(from: "W9XYZ", to: "K1ABC", dB: -7))
    }

    @Test("Parse RRR message")
    func parseRRR() {
        let msg = FT8Message.parse("K1ABC W9XYZ RRR")
        #expect(msg == .roger(from: "W9XYZ", to: "K1ABC"))
    }

    @Test("Parse 73 message")
    func parse73() {
        let msg = FT8Message.parse("K1ABC W9XYZ 73")
        #expect(msg == .end(from: "W9XYZ", to: "K1ABC"))
    }

    @Test("Parse free text with 4+ tokens")
    func parseFreeText() {
        let msg = FT8Message.parse("TNX BOB 73 GL")
        #expect(msg == .freeText("TNX BOB 73 GL"))
    }

    @Test("Parse positive signal report")
    func parsePositiveReport() {
        let msg = FT8Message.parse("W9XYZ K1ABC +05")
        #expect(msg == .signalReport(from: "K1ABC", to: "W9XYZ", dB: 5))
    }

    @Test("Parse positive roger report")
    func parsePositiveRogerReport() {
        let msg = FT8Message.parse("K1ABC W9XYZ R+03")
        #expect(msg == .rogerReport(from: "W9XYZ", to: "K1ABC", dB: 3))
    }

    // MARK: - FT8DecodeResult

    @Test("FT8DecodeResult initializes correctly")
    func decodeResult() {
        let message = FT8Message.cq(call: "K1ABC", grid: "FN42", modifier: nil)
        let result = FT8DecodeResult(
            message: message,
            snr: -14,
            deltaTime: 0.3,
            frequency: 1_200.0,
            rawText: "CQ K1ABC FN42"
        )
        #expect(result.message == message)
        #expect(result.snr == -14)
        #expect(result.deltaTime == 0.3)
        #expect(result.frequency == 1_200.0)
        #expect(result.rawText == "CQ K1ABC FN42")
    }

    // MARK: - Equatable/Hashable

    @Test("FT8Message is equatable")
    func messageEquatable() {
        let a = FT8Message.cq(call: "K1ABC", grid: "FN42", modifier: nil)
        let b = FT8Message.cq(call: "K1ABC", grid: "FN42", modifier: nil)
        let other = FT8Message.cq(call: "W9XYZ", grid: "EN37", modifier: nil)
        #expect(a == b)
        #expect(a != other)
    }

    @Test("Out-of-range grid letters parsed as free text")
    func outOfRangeGridLetters() {
        // Maidenhead grids use A-R only; 'Z' is out of range
        let msg = FT8Message.parse("K1ABC W9XYZ ZZ99")
        #expect(msg == .freeText("K1ABC W9XYZ ZZ99"))
    }

    @Test("CQ with empty grid returns nil for grid property")
    func cqEmptyGrid() {
        let msg = FT8Message.cq(call: "K1ABC", grid: "", modifier: nil)
        #expect(msg.grid == nil)
    }
}
