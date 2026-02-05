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
}
