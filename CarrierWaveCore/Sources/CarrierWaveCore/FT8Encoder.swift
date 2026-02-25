//
//  FT8Encoder.swift
//  CarrierWaveCore
//

import CFT8
import Foundation

// MARK: - FT8Encoder

/// Encodes FT8 messages into audio tone sequences using ft8_lib.
public enum FT8Encoder: Sendable {
    // MARK: Public

    /// Encode an FT8 message string into audio samples.
    ///
    /// - Parameters:
    ///   - message: The FT8 message text (e.g., "CQ K1ABC FN42").
    ///   - frequency: Audio frequency in Hz for the base tone. Default 1500.
    ///   - sampleRate: Output sample rate. Default 12000.
    /// - Returns: Array of Float audio samples representing the FT8 transmission.
    /// - Throws: `FT8Error.encodingFailed` if the message cannot be encoded.
    public static func encode(
        message: String,
        frequency: Double = 1_500.0,
        sampleRate: Int = FT8Constants.sampleRate
    ) throws -> [Float] {
        guard !message.isEmpty else {
            throw FT8Error.encodingFailed("Empty message")
        }

        let tones = try packAndEncode(message: message)
        return synthesizeTones(tones, frequency: frequency, sampleRate: sampleRate)
    }

    // MARK: Private

    /// Pack a message string into 77-bit payload and generate the 79-symbol tone sequence.
    private static func packAndEncode(message: String) throws -> [UInt8] {
        var ftxMessage = ftx_message_t()
        ftx_message_init(&ftxMessage)

        let rc = message.withCString { cStr in
            ftx_message_encode(&ftxMessage, nil, cStr)
        }

        guard rc == FTX_MESSAGE_RC_OK else {
            throw FT8Error.encodingFailed(
                "ft8_lib encode failed with code \(rc.rawValue) for: \(message)"
            )
        }

        var tones = [UInt8](repeating: 0, count: Int(FT8_NN))
        withUnsafePointer(to: &ftxMessage.payload) { payloadPtr in
            payloadPtr.withMemoryRebound(to: UInt8.self, capacity: Int(FTX_PAYLOAD_LENGTH_BYTES)) { ptr in
                ft8_encode(ptr, &tones)
            }
        }

        return tones
    }

    /// Generate audio samples from a tone sequence using continuous-phase FSK.
    ///
    /// Each symbol is `symbolPeriod` seconds. Tones are 8-FSK with `toneSpacing` Hz spacing.
    /// Phase is continuous across symbol boundaries for clean modulation.
    private static func synthesizeTones(
        _ tones: [UInt8],
        frequency: Double,
        sampleRate: Int
    ) -> [Float] {
        let symbolSamples = Int(Double(sampleRate) * FT8Constants.symbolPeriod)
        let totalSamples = tones.count * symbolSamples
        var samples = [Float](repeating: 0, count: totalSamples)

        let twoPi = 2.0 * Double.pi
        var phase = 0.0

        for (symbolIndex, tone) in tones.enumerated() {
            let toneFrequency = frequency + Double(tone) * FT8Constants.toneSpacing
            let phaseIncrement = twoPi * toneFrequency / Double(sampleRate)

            for sampleOffset in 0 ..< symbolSamples {
                let idx = symbolIndex * symbolSamples + sampleOffset
                samples[idx] = Float(sin(phase))
                phase += phaseIncrement
                if phase > twoPi {
                    phase -= twoPi
                }
            }
        }

        return samples
    }
}
