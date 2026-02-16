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

    // MARK: - Canonical Name Tests

    @Test("PHONE normalizes to SSB")
    func phoneCanonicalName() {
        #expect(ModeEquivalence.canonicalName("PHONE") == "SSB")
        #expect(ModeEquivalence.canonicalName("phone") == "SSB")
    }

    @Test("Specific modes keep their names")
    func specificCanonicalNames() {
        #expect(ModeEquivalence.canonicalName("SSB") == "SSB")
        #expect(ModeEquivalence.canonicalName("USB") == "USB")
        #expect(ModeEquivalence.canonicalName("CW") == "CW")
        #expect(ModeEquivalence.canonicalName("FT8") == "FT8")
        #expect(ModeEquivalence.canonicalName("DATA") == "DATA")
    }

    // MARK: - Deduplicated Modes Tests

    @Test("PHONE and SSB dedup to SSB")
    func deduplicatePhoneAndSSB() {
        let result = ModeEquivalence.deduplicatedModes(["PHONE", "SSB"])
        #expect(result == ["SSB"])
    }

    @Test("PHONE alone becomes SSB")
    func deduplicatePhoneAlone() {
        let result = ModeEquivalence.deduplicatedModes(["PHONE"])
        #expect(result == ["SSB"])
    }

    @Test("Mixed modes dedup correctly")
    func deduplicateMixedModes() {
        let result = ModeEquivalence.deduplicatedModes(["PHONE", "SSB", "CW", "FT8"])
        #expect(result == ["CW", "FT8", "SSB"])
    }

    @Test("SSB preferred over PHONE in dedup")
    func deduplicatePreferSpecific() {
        let result = ModeEquivalence.deduplicatedModes(["PHONE", "SSB", "CW"])
        #expect(result == ["CW", "SSB"])
    }

    @Test("Digital modes dedup by family")
    func deduplicateDigitalModes() {
        let result = ModeEquivalence.deduplicatedModes(["DATA", "FT8"])
        #expect(result == ["FT8"])
    }

    @Test("No duplicates when already unique")
    func deduplicateAlreadyUnique() {
        let result = ModeEquivalence.deduplicatedModes(["CW", "SSB", "FT8"])
        #expect(result == ["CW", "FT8", "SSB"])
    }
}
