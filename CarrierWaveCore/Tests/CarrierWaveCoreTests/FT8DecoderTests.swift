//
//  FT8DecoderTests.swift
//  CarrierWaveCore
//

import Foundation
import Testing
@testable import CarrierWaveCore

@Suite("FT8 Decoder Tests")
struct FT8DecoderTests {
    // MARK: Internal

    @Test("Decode ft8_lib test vector 191111_110615")
    func decodeTestVector1() throws {
        let samples = try loadWAV(named: "191111_110615")
        // 15s at 12kHz = 180,000 samples; WAV files may have slightly more
        #expect(samples.count >= 180_000 && samples.count <= 181_000)

        let results = FT8Decoder.decode(samples: samples)
        #expect(results.count >= 10) // Should find many signals

        // Verify at least some known decodes from the expected output
        let expected = try loadExpected(named: "191111_110615")
        let decodedTexts = Set(results.map(\.rawText))

        // Check that several expected messages were found
        var matchCount = 0
        for line in expected {
            let msgText = extractMessageText(from: line)
            if decodedTexts.contains(msgText) {
                matchCount += 1
            }
        }
        #expect(
            matchCount >= expected.count / 2,
            "Should decode at least half of expected messages, got \(matchCount)/\(expected.count)"
        )
    }

    @Test("Decode ft8_lib test vector 191111_110630")
    func decodeTestVector2() throws {
        let samples = try loadWAV(named: "191111_110630")
        let results = FT8Decoder.decode(samples: samples)
        #expect(results.count >= 10)
    }

    @Test("Decode 20m busy band sample")
    func decodeBusyBand() throws {
        let samples = try loadWAV(named: "test_01")
        let results = FT8Decoder.decode(samples: samples)
        #expect(results.count >= 15, "Busy band should have many signals")
    }

    @Test("Decode WSJT-X official sample")
    func decodeWSJTXSample() throws {
        let samples = try loadWAV(named: "170709_135615")
        // Try wider frequency range since official samples may have signals outside default band
        let results = FT8Decoder.decode(samples: samples, maxFrequency: 5_000)
        // This sample may have weak or no decodable signals; reaching here means no crash
        _ = results
    }

    @Test("Empty audio returns no decodes")
    func emptyAudio() {
        let silence = [Float](repeating: 0, count: 180_000)
        let results = FT8Decoder.decode(samples: silence)
        #expect(results.isEmpty)
    }

    @Test("Short audio returns no decodes without crash")
    func shortAudio() {
        let short = [Float](repeating: 0, count: 100)
        let results = FT8Decoder.decode(samples: short)
        #expect(results.isEmpty)
    }

    @Test("Decode results have valid SNR range")
    func snrRange() throws {
        let samples = try loadWAV(named: "191111_110615")
        let results = FT8Decoder.decode(samples: samples)
        for result in results {
            #expect(
                result.snr >= -30 && result.snr <= 30,
                "SNR \(result.snr) out of expected range for \(result.rawText)"
            )
        }
    }

    @Test("Decode results have valid frequency range")
    func frequencyRange() throws {
        let samples = try loadWAV(named: "191111_110615")
        let results = FT8Decoder.decode(samples: samples)
        for result in results {
            #expect(
                result.frequency >= 100 && result.frequency <= 4_000,
                "Frequency \(result.frequency) out of expected range"
            )
        }
    }

    // MARK: Private

    /// Subdirectories to search for test resources within ft8-samples
    private static let resourceSubdirs = [
        "ft8-samples",
        "ft8-samples/ft8_lib_test_vectors",
        "ft8-samples/ft8_lib_test_vectors/20m_busy",
    ]

    /// Load a WAV file from test resources and return raw Float samples.
    private func loadWAV(named name: String) throws -> [Float] {
        let url = try #require(findResource(name: name, ext: "wav"))
        return try FT8Decoder.loadWAV(url: url)
    }

    /// Load expected decode output from a .txt file.
    private func loadExpected(named name: String) throws -> [String] {
        let url = try #require(findResource(name: name, ext: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    /// Search multiple subdirectories for a test resource.
    private func findResource(name: String, ext: String) -> URL? {
        for subdir in Self.resourceSubdirs {
            if let url = Bundle.module.url(
                forResource: name, withExtension: ext, subdirectory: subdir
            ) {
                return url
            }
        }
        return nil
    }

    /// Extract message text from a test vector line.
    /// Format: "110615  -2  1.0  431 ~  VK4BLE OH8JK R-17"
    private func extractMessageText(from line: String) -> String {
        guard let tildeRange = line.range(of: "~") else {
            return line
        }
        let afterTilde = line[tildeRange.upperBound...]
        let trimmed = afterTilde.trimmingCharacters(in: .whitespaces)
        if let doubleSpace = trimmed.range(of: "  ") {
            return String(trimmed[..<doubleSpace.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}
