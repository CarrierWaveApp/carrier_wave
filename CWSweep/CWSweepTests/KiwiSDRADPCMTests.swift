import Foundation
import Testing
@testable import CWSweep

// MARK: - ADPCM Decoder Tests

@Test func adpcmDecodeEmptyData() {
    var state = KiwiSDRADPCM.DecoderState()
    let samples = KiwiSDRADPCM.decode(Data(), state: &state)
    #expect(samples.isEmpty)
}

@Test func adpcmDecodeProducesTwoSamplesPerByte() {
    var state = KiwiSDRADPCM.DecoderState()
    let input = Data([0x00, 0x00, 0x00])
    let samples = KiwiSDRADPCM.decode(input, state: &state)
    #expect(samples.count == 6)
}

@Test func adpcmDecodeSilence() {
    // Decoding all zeros should produce near-zero samples
    var state = KiwiSDRADPCM.DecoderState()
    let input = Data(repeating: 0x00, count: 10)
    let samples = KiwiSDRADPCM.decode(input, state: &state)
    #expect(samples.count == 20)

    // All samples should be within a small range of 0
    for sample in samples {
        #expect(abs(sample) < 100, "Sample \(sample) should be near zero for silence input")
    }
}

@Test func adpcmDecodeClamps() {
    // Feed extreme nibbles to test clamping to Int16 range
    var state = KiwiSDRADPCM.DecoderState()

    // Ramp up with high positive nibbles
    let rampUp = Data(repeating: 0x77, count: 100) // nibble 7 = max positive step
    let samples = KiwiSDRADPCM.decode(rampUp, state: &state)

    // Should never exceed Int16 range
    for sample in samples {
        #expect(sample >= Int16.min)
        #expect(sample <= Int16.max)
    }
}

@Test func adpcmDecoderStatePreserved() {
    var state = KiwiSDRADPCM.DecoderState()
    #expect(state.predictor == 0)
    #expect(state.stepIndex == 0)

    // Decode some data to change state
    let input = Data([0x37, 0x45, 0x12])
    _ = KiwiSDRADPCM.decode(input, state: &state)

    // State should be modified
    #expect(state.predictor != 0 || state.stepIndex != 0,
            "Decoder state should change after processing non-trivial data")
}

@Test func adpcmDecodeConsistentResults() {
    // Same input should produce same output
    let input = Data([0x12, 0x34, 0x56, 0x78, 0x9A])

    var state1 = KiwiSDRADPCM.DecoderState()
    let samples1 = KiwiSDRADPCM.decode(input, state: &state1)

    var state2 = KiwiSDRADPCM.DecoderState()
    let samples2 = KiwiSDRADPCM.decode(input, state: &state2)

    #expect(samples1 == samples2)
    #expect(state1.predictor == state2.predictor)
    #expect(state1.stepIndex == state2.stepIndex)
}
