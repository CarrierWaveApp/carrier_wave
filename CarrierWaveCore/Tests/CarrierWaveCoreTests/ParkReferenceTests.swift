//
//  ParkReferenceTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("Park Reference Tests")
struct ParkReferenceTests {
    // MARK: - Splitting Tests

    @Test("Split single park reference")
    func splitSinglePark() {
        let parks = ParkReference.split("US-0189")
        #expect(parks == ["US-0189"])
    }

    @Test("Split multi-park reference (two-fer)")
    func splitTwofer() {
        let parks = ParkReference.split("US-1044, US-3791")
        #expect(parks == ["US-1044", "US-3791"])
    }

    @Test("Split handles whitespace")
    func splitHandlesWhitespace() {
        let parks = ParkReference.split("  US-1044 ,  US-3791  ")
        #expect(parks == ["US-1044", "US-3791"])
    }

    @Test("Split handles no spaces")
    func splitNoSpaces() {
        let parks = ParkReference.split("US-1044,US-3791")
        #expect(parks == ["US-1044", "US-3791"])
    }

    @Test("Split normalizes to uppercase")
    func splitUppercase() {
        let parks = ParkReference.split("us-1044, k-0001")
        #expect(parks == ["US-1044", "K-0001"])
    }

    // MARK: - Multi-Park Detection

    @Test("Detect multi-park reference")
    func detectMultiPark() {
        #expect(ParkReference.isMultiPark("US-1044, US-3791"))
        #expect(ParkReference.isMultiPark("US-1044,US-3791,US-9999"))
        #expect(!ParkReference.isMultiPark("US-1044"))
        #expect(!ParkReference.isMultiPark(""))
    }

    // MARK: - Validation Tests

    @Test("Valid park references")
    func validParkReferences() {
        #expect(ParkReference.isValid("US-0189"))
        #expect(ParkReference.isValid("K-1234"))
        #expect(ParkReference.isValid("VE-0001"))
        #expect(ParkReference.isValid("G-0001"))
        #expect(ParkReference.isValid("JA-12345"))
    }

    @Test("Invalid park references")
    func invalidParkReferences() {
        #expect(!ParkReference.isValid("US0189")) // Missing dash
        #expect(!ParkReference.isValid("US-01")) // Too short
        #expect(!ParkReference.isValid("USA-0189")) // Prefix too long
        #expect(!ParkReference.isValid("US-123456")) // Too many digits
        #expect(!ParkReference.isValid("")) // Empty
        #expect(!ParkReference.isValid("W1AW")) // Callsign
    }

    // MARK: - Normalization Tests

    @Test("Normalize single park")
    func normalizeSingle() {
        #expect(ParkReference.normalize("  us-0189  ") == "US-0189")
        #expect(ParkReference.normalize("k-1234") == "K-1234")
    }

    @Test("Normalize multi-park (sorted)")
    func normalizeMulti() {
        #expect(ParkReference.normalizeMulti("US-3791, US-1044") == "US-1044, US-3791")
        #expect(ParkReference.normalizeMulti("K-0002, K-0001, K-0003") == "K-0001, K-0002, K-0003")
    }

    // MARK: - Subset Tests

    @Test("Single park is subset of multi-park")
    func singleIsSubsetOfMulti() {
        #expect(ParkReference.isSubset("US-1044", of: "US-1044, US-3791"))
        #expect(ParkReference.isSubset("US-3791", of: "US-1044, US-3791"))
    }

    @Test("Multi-park is subset of itself")
    func multiIsSubsetOfSelf() {
        #expect(ParkReference.isSubset("US-1044, US-3791", of: "US-1044, US-3791"))
    }

    @Test("Different park is not subset")
    func differentNotSubset() {
        #expect(!ParkReference.isSubset("US-9999", of: "US-1044, US-3791"))
    }

    @Test("Superset is not subset")
    func supersetNotSubset() {
        #expect(!ParkReference.isSubset("US-1044, US-3791, US-9999", of: "US-1044, US-3791"))
    }

    // MARK: - Overlap Tests

    @Test("Parks have overlap")
    func hasOverlap() {
        #expect(ParkReference.hasOverlap("US-1044", "US-1044, US-3791"))
        #expect(ParkReference.hasOverlap("US-1044, US-9999", "US-1044, US-3791"))
    }

    @Test("Parks have no overlap")
    func noOverlap() {
        #expect(!ParkReference.hasOverlap("US-9999", "US-1044, US-3791"))
        #expect(!ParkReference.hasOverlap("K-0001", "US-1044"))
    }

    // MARK: - Sanitize Tests

    @Test("Sanitize valid park reference passes through unchanged")
    func sanitizeValidPassthrough() {
        #expect(ParkReference.sanitize("US-0189") == "US-0189")
        #expect(ParkReference.sanitize("K-1234") == "K-1234")
        #expect(ParkReference.sanitize("JA-12345") == "JA-12345")
    }

    @Test("Sanitize fixes missing dash")
    func sanitizeFixesMissingDash() {
        #expect(ParkReference.sanitize("US1849") == "US-1849")
        #expect(ParkReference.sanitize("K0001") == "K-0001")
        #expect(ParkReference.sanitize("VE12345") == "VE-12345")
    }

    @Test("Sanitize returns nil for bare numbers")
    func sanitizeBareNumbersNil() {
        #expect(ParkReference.sanitize("3687") == nil)
        #expect(ParkReference.sanitize("11027") == nil)
    }

    @Test("Sanitize returns nil for empty or invalid input")
    func sanitizeInvalidNil() {
        #expect(ParkReference.sanitize("") == nil)
        #expect(ParkReference.sanitize("W1AW") == nil)
        #expect(ParkReference.sanitize("US-01") == nil)
        #expect(ParkReference.sanitize("USA-0189") == nil)
    }

    @Test("Sanitize normalizes to uppercase")
    func sanitizeUppercases() {
        #expect(ParkReference.sanitize("us-0189") == "US-0189")
        #expect(ParkReference.sanitize("k1234") == "K-1234")
    }

    @Test("SanitizeMulti handles mixed valid and invalid parks")
    func sanitizeMultiMixed() {
        #expect(ParkReference.sanitizeMulti("US-1037, 3687") == "US-1037")
        #expect(ParkReference.sanitizeMulti("US-1044, US-3791") == "US-1044, US-3791")
    }

    @Test("SanitizeMulti fixes missing dashes in multi-park")
    func sanitizeMultiFixesDashes() {
        #expect(ParkReference.sanitizeMulti("US1849, US3687") == "US-1849, US-3687")
    }

    @Test("SanitizeMulti returns nil when all parks invalid")
    func sanitizeMultiAllInvalid() {
        #expect(ParkReference.sanitizeMulti("3687, 11027") == nil)
        #expect(ParkReference.sanitizeMulti("") == nil)
    }

    // MARK: - Free Text Extraction Tests

    @Test("Extract park reference from WSJT-X style comment")
    func extractFromCommentSimple() {
        #expect(ParkReference.extractFromFreeText("K-1234") == "K-1234")
        #expect(ParkReference.extractFromFreeText("POTA K-1234") == "K-1234")
        #expect(ParkReference.extractFromFreeText("at US-0189") == "US-0189")
    }

    @Test("Extract park reference embedded in longer text")
    func extractFromCommentEmbedded() {
        #expect(ParkReference.extractFromFreeText("Activating K-1234 today") == "K-1234")
        #expect(ParkReference.extractFromFreeText("POTA US-0189 FT8") == "US-0189")
    }

    @Test("Extract multiple park references from comment (two-fer)")
    func extractFromCommentMultiple() {
        let result = ParkReference.extractFromFreeText("K-1234, US-0189")
        #expect(result == "K-1234, US-0189")
    }

    @Test("Extract deduplicates repeated park references")
    func extractFromCommentDedup() {
        let result = ParkReference.extractFromFreeText("K-1234 K-1234")
        #expect(result == "K-1234")
    }

    @Test("Extract returns nil when no park references found")
    func extractFromCommentNone() {
        #expect(ParkReference.extractFromFreeText("just a normal comment") == nil)
        #expect(ParkReference.extractFromFreeText("W1AW on 20m") == nil)
        #expect(ParkReference.extractFromFreeText("") == nil)
    }

    @Test("Extract is case insensitive")
    func extractFromCommentCaseInsensitive() {
        #expect(ParkReference.extractFromFreeText("pota k-1234") == "K-1234")
        #expect(ParkReference.extractFromFreeText("us-0189") == "US-0189")
    }
}
