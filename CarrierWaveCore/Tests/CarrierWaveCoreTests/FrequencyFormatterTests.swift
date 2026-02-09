//
//  FrequencyFormatterTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("FrequencyFormatter Tests")
struct FrequencyFormatterTests {
    // MARK: - Parse: Standard decimal input

    @Test("Parse standard MHz decimal")
    func parseStandardMHz() {
        #expect(FrequencyFormatter.parse("14.060") == 14.060)
        #expect(FrequencyFormatter.parse("7.030") == 7.030)
        #expect(FrequencyFormatter.parse("28.400") == 28.400)
        #expect(FrequencyFormatter.parse("144.000") == 144.000)
    }

    @Test("Parse kHz auto-conversion")
    func parseKHzAutoConversion() throws {
        let result = FrequencyFormatter.parse("14060")
        #expect(result != nil)
        #expect(try abs(#require(result) - 14.060) < 0.0001)
    }

    @Test("Parse with explicit MHz suffix")
    func parseExplicitMHz() {
        #expect(FrequencyFormatter.parse("14.060 MHz") == 14.060)
        #expect(FrequencyFormatter.parse("14.060MHz") == 14.060)
        #expect(FrequencyFormatter.parse("14.060 mhz") == 14.060)
    }

    @Test("Parse with explicit kHz suffix")
    func parseExplicitKHz() throws {
        let result = FrequencyFormatter.parse("14060 kHz")
        #expect(result != nil)
        #expect(try abs(#require(result) - 14.060) < 0.0001)
    }

    @Test("Parse returns nil for invalid input")
    func parseInvalidInput() {
        #expect(FrequencyFormatter.parse("") == nil)
        #expect(FrequencyFormatter.parse("abc") == nil)
        #expect(FrequencyFormatter.parse("0.5") == nil) // Below amateur range
    }

    // MARK: - Parse: Dot-separated ham radio notation

    @Test("Parse dot-separated MHz.kHz.Hz notation")
    func parseDotSeparated() throws {
        // 14.030.50 = 14 MHz + 030 kHz + 50 (tens of Hz) = 14.03050 MHz
        let result = FrequencyFormatter.parse("14.030.50")
        #expect(result != nil)
        #expect(try abs(#require(result) - 14.03050) < 0.00001)
    }

    @Test("Parse dot-separated with trailing zeros")
    func parseDotSeparatedTrailingZeros() throws {
        // 7.030.00 = 7.03000 MHz = 7.030 MHz
        let result = FrequencyFormatter.parse("7.030.00")
        #expect(result != nil)
        #expect(try abs(#require(result) - 7.030) < 0.00001)
    }

    @Test("Parse dot-separated with 3-digit Hz part")
    func parseDotSeparatedThreeDigitHz() throws {
        // 14.030.500 = 14.030500 MHz = 14.0305 MHz
        let result = FrequencyFormatter.parse("14.030.500")
        #expect(result != nil)
        #expect(try abs(#require(result) - 14.0305) < 0.00001)
    }

    @Test("Parse dot-separated on different bands")
    func parseDotSeparatedDifferentBands() throws {
        // 7.040.50 = 7.04050 MHz
        let result40m = FrequencyFormatter.parse("7.040.50")
        #expect(result40m != nil)
        #expect(try abs(#require(result40m) - 7.04050) < 0.00001)

        // 21.060.00 = 21.06000 MHz = 21.060 MHz
        let result15m = FrequencyFormatter.parse("21.060.00")
        #expect(result15m != nil)
        #expect(try abs(#require(result15m) - 21.060) < 0.00001)
    }

    @Test("Reject too many dots")
    func rejectTooManyDots() {
        #expect(FrequencyFormatter.parse("1.2.3.4") == nil)
    }

    @Test("Reject dot-separated with non-numeric parts")
    func rejectDotSeparatedNonNumeric() {
        #expect(FrequencyFormatter.parse("14.abc.50") == nil)
        #expect(FrequencyFormatter.parse("14.030.xy") == nil)
    }

    @Test("Reject dot-separated with empty parts")
    func rejectDotSeparatedEmptyParts() {
        #expect(FrequencyFormatter.parse(".030.50") == nil)
        #expect(FrequencyFormatter.parse("14..50") == nil)
    }

    // MARK: - Format

    @Test("Format with minimum 3 decimal places")
    func formatMinimumDecimals() {
        #expect(FrequencyFormatter.format(14.060) == "14.060")
        #expect(FrequencyFormatter.format(7.000) == "7.000")
    }

    @Test("Format with sub-kHz precision")
    func formatSubKHz() {
        #expect(FrequencyFormatter.format(14.03050) == "14.0305")
        #expect(FrequencyFormatter.format(14.03055) == "14.03055")
    }

    @Test("Format with unit")
    func formatWithUnit() {
        #expect(FrequencyFormatter.formatWithUnit(14.060) == "14.060 MHz")
    }
}
