import Foundation

/// IMA ADPCM decoder for KiwiSDR compressed audio streams.
/// KiwiSDR uses IMA ADPCM (4:1 compression) for mono audio modes.
nonisolated enum KiwiSDRADPCM {
    // MARK: Internal

    /// Mutable decoder state carried between frames
    struct DecoderState {
        var predictor: Int32 = 0
        var stepIndex: Int = 0
    }

    /// Decode IMA ADPCM data to Int16 PCM samples.
    /// Each input byte produces two output samples (4 bits per sample).
    static func decode(_ data: Data, state: inout DecoderState) -> [Int16] {
        var samples: [Int16] = []
        samples.reserveCapacity(data.count * 2)

        for byte in data {
            samples.append(decodeNibble(byte & 0x0F, state: &state))
            samples.append(decodeNibble(byte >> 4, state: &state))
        }

        return samples
    }

    // MARK: Private

    private static let stepTable: [Int32] = [
        7, 8, 9, 10, 11, 12, 13, 14,
        16, 17, 19, 21, 23, 25, 28, 31,
        34, 37, 41, 45, 50, 55, 60, 66,
        73, 80, 88, 97, 107, 118, 130, 143,
        157, 173, 190, 209, 230, 253, 279, 307,
        337, 371, 408, 449, 494, 544, 598, 658,
        724, 796, 876, 963, 1_060, 1_166, 1_282, 1_411,
        1_552, 1_707, 1_878, 2_066, 2_272, 2_499, 2_749, 3_024,
        3_327, 3_660, 4_026, 4_428, 4_871, 5_358, 5_894, 6_484,
        7_132, 7_845, 8_630, 9_493, 10_442, 11_487, 12_635, 13_899,
        15_289, 16_818, 18_500, 20_350, 22_385, 24_623, 27_086, 29_794,
        32_767,
    ]

    private static let indexTable: [Int] = [
        -1, -1, -1, -1, 2, 4, 6, 8,
        -1, -1, -1, -1, 2, 4, 6, 8,
    ]

    private static func decodeNibble(_ nibble: UInt8, state: inout DecoderState) -> Int16 {
        let step = stepTable[state.stepIndex]

        state.stepIndex += indexTable[Int(nibble)]
        state.stepIndex = max(0, min(88, state.stepIndex))

        var diff = step >> 3
        if nibble & 4 != 0 {
            diff += step
        }
        if nibble & 2 != 0 {
            diff += step >> 1
        }
        if nibble & 1 != 0 {
            diff += step >> 2
        }

        if nibble & 8 != 0 {
            state.predictor -= diff
        } else {
            state.predictor += diff
        }

        state.predictor = max(-32_768, min(32_767, state.predictor))

        return Int16(state.predictor)
    }
}
