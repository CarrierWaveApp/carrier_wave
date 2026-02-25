//
//  FT8EncoderTests.swift
//  CarrierWaveCore
//

import Testing
@testable import CarrierWaveCore

@Suite("FT8 Encoder Tests")
struct FT8EncoderTests {
    // MARK: Internal

    @Test("Encode CQ message produces correct sample count")
    func encodeCQSampleCount() throws {
        let samples = try FT8Encoder.encode(message: "CQ K1ABC FN42")
        #expect(samples.count == expectedSampleCount)
    }

    @Test("Encoded audio is not silence")
    func encodedNotSilence() throws {
        let samples = try FT8Encoder.encode(message: "CQ K1ABC FN42")
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        #expect(maxAmplitude > 0.01, "Encoded audio should not be silence")
    }

    @Test("Encoded audio amplitude is normalized")
    func encodedAmplitudeNormalized() throws {
        let samples = try FT8Encoder.encode(message: "CQ K1ABC FN42")
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        #expect(maxAmplitude <= 1.0, "Amplitude should not exceed 1.0")
        #expect(maxAmplitude > 0.5, "Amplitude should be reasonably loud")
    }

    @Test("Round-trip: encode then decode recovers message")
    func roundTrip() throws {
        let originalMessage = "CQ K1ABC FN42"
        let encoded = try FT8Encoder.encode(message: originalMessage, frequency: 1_500)

        // Pad to 15 seconds (decoder expects a full slot)
        var padded = [Float](repeating: 0, count: FT8Constants.samplesPerSlot)
        for idx in 0 ..< min(encoded.count, padded.count) {
            padded[idx] = encoded[idx]
        }

        let results = FT8Decoder.decode(samples: padded)
        let texts = results.map(\.rawText)
        #expect(
            texts.contains("CQ K1ABC FN42"),
            "Round-trip should recover the original message (\(results.count) decoded). Got: \(texts)"
        )
    }

    @Test("Encode signal report message")
    func encodeSignalReport() throws {
        let samples = try FT8Encoder.encode(message: "W9XYZ K1ABC -11")
        #expect(samples.count == expectedSampleCount)
    }

    @Test("Encode RR73 message")
    func encodeRR73() throws {
        let samples = try FT8Encoder.encode(message: "W9XYZ K1ABC RR73")
        #expect(samples.count == expectedSampleCount)
    }

    @Test("Encode free text message")
    func encodeFreeText() throws {
        let samples = try FT8Encoder.encode(message: "TNX BOB 73 GL")
        #expect(samples.count == expectedSampleCount)
    }

    @Test("Encode CQ POTA message")
    func encodeCQPOTA() throws {
        let samples = try FT8Encoder.encode(message: "CQ POTA K7ABC CN87")
        #expect(samples.count == expectedSampleCount)
    }

    @Test("Invalid message returns error")
    func invalidMessage() {
        #expect(throws: FT8Error.self) {
            _ = try FT8Encoder.encode(message: "")
        }
    }

    @Test("Different frequencies produce different audio")
    func differentFrequencies() throws {
        let at1000 = try FT8Encoder.encode(message: "CQ K1ABC FN42", frequency: 1_000)
        let at2000 = try FT8Encoder.encode(message: "CQ K1ABC FN42", frequency: 2_000)
        // Same length but different content
        #expect(at1000.count == at2000.count)
        #expect(at1000 != at2000)
    }

    // MARK: Private

    /// Expected sample count: 79 symbols * 0.160s * 12000 Hz = 151,680
    private var expectedSampleCount: Int {
        FT8Constants.totalSymbols * Int(Double(FT8Constants.sampleRate) * FT8Constants.symbolPeriod)
    }
}
