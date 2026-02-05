//
//  MorseEditDistanceTests.swift
//  CarrierWaveCoreTests
//

import Testing
@testable import CarrierWaveCore

@Suite("Morse Edit Distance Tests")
struct MorseEditDistanceTests {
    @Test("Pattern distance - identical patterns")
    func patternDistanceIdentical() {
        #expect(MorseEditDistance.patternDistance(".-", ".-") == 0)
        #expect(MorseEditDistance.patternDistance("-.-.--", "-.-.--") == 0)
    }

    @Test("Pattern distance - single character difference")
    func patternDistanceSingleDiff() {
        // Dit vs dah is one substitution
        #expect(MorseEditDistance.patternDistance(".", "-") == 1)
        #expect(MorseEditDistance.patternDistance(".-", "--") == 1)
    }

    @Test("Pattern distance - insertions and deletions")
    func patternDistanceInsertDelete() {
        #expect(MorseEditDistance.patternDistance(".-", ".") == 1) // deletion
        #expect(MorseEditDistance.patternDistance(".", ".-") == 1) // insertion
        #expect(MorseEditDistance.patternDistance("", ".-") == 2) // two insertions
    }

    @Test("Pattern distance - empty strings")
    func patternDistanceEmpty() {
        #expect(MorseEditDistance.patternDistance("", "") == 0)
        #expect(MorseEditDistance.patternDistance(".-", "") == 2)
        #expect(MorseEditDistance.patternDistance("", ".-") == 2)
    }

    @Test("Word to morse conversion")
    func wordToMorse() {
        // CQ = -.-. --.-
        #expect(MorseEditDistance.wordToMorse("CQ") == "-.-.--.-")
        // SOS = ... --- ...
        #expect(MorseEditDistance.wordToMorse("SOS") == "...---...")
        // A = .-
        #expect(MorseEditDistance.wordToMorse("A") == ".-")
    }

    @Test("Word to morse - invalid characters")
    func wordToMorseInvalid() {
        // Characters not in morse table return nil
        #expect(MorseEditDistance.wordToMorse("@#$") == nil)
        #expect(MorseEditDistance.wordToMorse("CQ{") == nil)
    }

    @Test("Word distance - similar words")
    func wordDistance() {
        // CQ and CZ differ by one character
        let distance = MorseEditDistance.wordDistance("CQ", "CZ")
        #expect(distance < 5) // Should be relatively close

        // Identical words
        #expect(MorseEditDistance.wordDistance("CQ", "CQ") == 0)
    }

    @Test("Word distance - invalid words")
    func wordDistanceInvalid() {
        // Characters not in morse table return Int.max
        #expect(MorseEditDistance.wordDistance("CQ{", "CQ") == Int.max)
        #expect(MorseEditDistance.wordDistance("CQ", "CQ{") == Int.max)
    }

    @Test("Find similar words")
    func findSimilar() {
        let candidates: Set<String> = ["CQ", "DE", "K", "AR", "SK"]
        let similar = MorseEditDistance.findSimilar(
            to: "CZ", maxDistance: 3, candidates: candidates
        )

        // Should find CQ as it's similar to CZ
        #expect(!similar.isEmpty)
        // Results should be sorted by distance
        if similar.count > 1 {
            #expect(similar[0].distance <= similar[1].distance)
        }
    }

    @Test("Find similar - exact match excluded")
    func findSimilarExactMatch() {
        let candidates: Set<String> = ["CQ", "DE", "K"]
        let similar = MorseEditDistance.findSimilar(
            to: "CQ", maxDistance: 3, candidates: candidates
        )

        // Exact match should not be in results
        #expect(!similar.contains { $0.word == "CQ" })
    }

    @Test("Find best match")
    func findBestMatch() {
        let candidates: Set<String> = ["CQ", "DE", "K", "AR"]
        let best = MorseEditDistance.findBestMatch(
            for: "CZ", maxDistance: 5, candidates: candidates
        )

        // Should find something
        #expect(best != nil)
    }

    @Test("Find best match - no match within distance")
    func findBestMatchNoMatch() {
        let candidates: Set<String> = ["CQ", "DE"]
        let best = MorseEditDistance.findBestMatch(
            for: "XYZABC", maxDistance: 1, candidates: candidates
        )

        // Very different word, should not match with low distance
        #expect(best == nil)
    }
}
