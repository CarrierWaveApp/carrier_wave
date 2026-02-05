//
//  ModeEquivalenceTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("Mode Equivalence Tests")
struct ModeEquivalenceTests {
    // MARK: - Mode Family Tests

    @Test("Phone modes are classified correctly")
    func phoneModeFamily() {
        #expect(ModeEquivalence.family(for: "SSB") == .phone)
        #expect(ModeEquivalence.family(for: "USB") == .phone)
        #expect(ModeEquivalence.family(for: "LSB") == .phone)
        #expect(ModeEquivalence.family(for: "AM") == .phone)
        #expect(ModeEquivalence.family(for: "FM") == .phone)
        #expect(ModeEquivalence.family(for: "PHONE") == .phone)
    }

    @Test("Digital modes are classified correctly")
    func digitalModeFamily() {
        #expect(ModeEquivalence.family(for: "FT8") == .digital)
        #expect(ModeEquivalence.family(for: "FT4") == .digital)
        #expect(ModeEquivalence.family(for: "RTTY") == .digital)
        #expect(ModeEquivalence.family(for: "PSK31") == .digital)
        #expect(ModeEquivalence.family(for: "DATA") == .digital)
    }

    @Test("CW is classified correctly")
    func cwModeFamily() {
        #expect(ModeEquivalence.family(for: "CW") == .cw)
    }

    @Test("Unknown modes are classified as other")
    func otherModeFamily() {
        #expect(ModeEquivalence.family(for: "UNKNOWN") == .other)
        #expect(ModeEquivalence.family(for: "XYZ") == .other)
    }

    // MARK: - Equivalence Tests

    @Test("Same mode is equivalent")
    func sameModeEquivalent() {
        #expect(ModeEquivalence.areEquivalent("SSB", "SSB"))
        #expect(ModeEquivalence.areEquivalent("CW", "CW"))
        #expect(ModeEquivalence.areEquivalent("FT8", "FT8"))
    }

    @Test("Phone modes are equivalent to each other")
    func phoneModeEquivalence() {
        #expect(ModeEquivalence.areEquivalent("SSB", "USB"))
        #expect(ModeEquivalence.areEquivalent("SSB", "LSB"))
        #expect(ModeEquivalence.areEquivalent("PHONE", "SSB"))
        #expect(ModeEquivalence.areEquivalent("AM", "FM"))
    }

    @Test("Digital modes are equivalent to each other")
    func digitalModeEquivalence() {
        #expect(ModeEquivalence.areEquivalent("FT8", "FT4"))
        #expect(ModeEquivalence.areEquivalent("DATA", "FT8"))
        #expect(ModeEquivalence.areEquivalent("RTTY", "PSK31"))
    }

    @Test("Different mode families are not equivalent")
    func differentFamiliesNotEquivalent() {
        #expect(!ModeEquivalence.areEquivalent("SSB", "CW"))
        #expect(!ModeEquivalence.areEquivalent("SSB", "FT8"))
        #expect(!ModeEquivalence.areEquivalent("CW", "FT8"))
    }

    @Test("Case insensitive comparison")
    func caseInsensitive() {
        #expect(ModeEquivalence.areEquivalent("ssb", "SSB"))
        #expect(ModeEquivalence.areEquivalent("Ft8", "FT8"))
    }

    // MARK: - More Specific Tests

    @Test("Specific mode preferred over generic")
    func specificOverGeneric() {
        #expect(ModeEquivalence.moreSpecific("PHONE", "SSB") == "SSB")
        #expect(ModeEquivalence.moreSpecific("SSB", "PHONE") == "SSB")
        #expect(ModeEquivalence.moreSpecific("DATA", "FT8") == "FT8")
        #expect(ModeEquivalence.moreSpecific("FT8", "DATA") == "FT8")
    }

    @Test("First mode returned when both specific")
    func bothSpecificReturnsFirst() {
        #expect(ModeEquivalence.moreSpecific("SSB", "USB") == "SSB")
        #expect(ModeEquivalence.moreSpecific("FT8", "FT4") == "FT8")
    }

    @Test("Generic mode detection")
    func genericModeDetection() {
        #expect(ModeEquivalence.isGeneric("PHONE"))
        #expect(ModeEquivalence.isGeneric("DATA"))
        #expect(!ModeEquivalence.isGeneric("SSB"))
        #expect(!ModeEquivalence.isGeneric("FT8"))
        #expect(!ModeEquivalence.isGeneric("CW"))
    }
}
