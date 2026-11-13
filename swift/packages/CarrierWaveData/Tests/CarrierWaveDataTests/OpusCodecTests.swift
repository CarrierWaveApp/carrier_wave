import CarrierWaveData
import Foundation
import Testing

// MARK: - OpusCodec availability

@Test func opusEncoderProbeReportsAvailability() {
    // We don't assert true — Apple's Opus encoder may not exist on every
    // OS this test runs on. We DO assert the probe doesn't crash and
    // returns a Bool, which is the contract Sweep depends on at startup.
    let available = OpusCodec.isEncoderAvailable()
    let _: Bool = available
}

@Test func opusDecoderProbeReportsAvailability() {
    let available = OpusCodec.isDecoderAvailable()
    let _: Bool = available
}

// MARK: - End-to-end round trip

@Test func opusRoundTripPreservesAudioStructure() throws {
    // If Apple's encoder/decoder pair isn't available, skip — this can
    // happen in headless CI without the audio frameworks present. The
    // production code path falls back to PCM in this case.
    guard OpusCodec.isEncoderAvailable(), OpusCodec.isDecoderAvailable() else {
        return
    }

    let config = OpusCodecConfig(sampleRate: 16_000)
    let encoder = try #require(OpusEncoder(config: config))
    let decoder = try #require(OpusDecoder(config: config))

    // 1 second of 1 kHz sine at 0.5 amplitude — plenty for the codec to
    // chew on, well within Opus's voice-mode sweet spot.
    let pcm = makeSinePCM(
        seconds: 1,
        sampleRate: config.sampleRate,
        toneHz: 1_000,
        amplitude: 0.5
    )

    let packets = try encoder.encode(pcmBytes: pcm)
    // 1 s / 20 ms frame = 50 packets exactly.
    #expect(packets.count == 50, "expected 50 Opus packets for 1 s of audio, got \(packets.count)")

    // Each packet should be small. Voice at 24 kbps / 50 pps = ~60 bytes
    // average. Allow a wide envelope so transients don't trip the test.
    for (idx, packet) in packets.enumerated() {
        #expect(
            !packet.isEmpty && packet.count < 600,
            "packet \(idx) size \(packet.count) outside reasonable range"
        )
    }

    var decodedPCM = Data()
    for packet in packets {
        if let frame = try decoder.decode(packet: packet) {
            decodedPCM.append(frame)
        }
    }

    // Opus has algorithmic delay — the first decoded packet is shorter
    // than `framesPerPacket` because the encoder needs lookahead samples
    // before it can produce its first output. 40 samples at 16 kHz is the
    // observed Apple behavior; we allow a small deficit but require the
    // bulk of the audio to come back.
    let expectedBytes = packets.count * config.framesPerPacket * MemoryLayout<Int16>.size
    #expect(decodedPCM.count <= expectedBytes)
    #expect(decodedPCM.count >= expectedBytes - 200, "decoder produced way fewer samples than expected")

    // Sanity: decoded RMS should be in the same ballpark as input RMS.
    // Opus is lossy; ±50 % of source amplitude is plenty of slack.
    let inputRMS = computeRMS(pcm: pcm)
    let outputRMS = computeRMS(pcm: decodedPCM)
    let ratio = outputRMS / max(inputRMS, 1e-6)
    #expect(
        ratio > 0.5 && ratio < 1.5,
        "decoded RMS ratio \(ratio) suggests pipeline silence or distortion"
    )
}

// MARK: - Encoder buffers partial frames

@Test func opusEncoderBuffersUntilFullPacket() throws {
    guard OpusCodec.isEncoderAvailable() else {
        return
    }
    let config = OpusCodecConfig(sampleRate: 16_000)
    let encoder = try #require(OpusEncoder(config: config))

    let bytesPerPacket = config.framesPerPacket * MemoryLayout<Int16>.size

    // Push half a frame; expect zero packets out.
    let halfFrame = Data(repeating: 0, count: bytesPerPacket / 2)
    #expect(try encoder.encode(pcmBytes: halfFrame).isEmpty)

    // Pushing the other half completes the frame; expect exactly one.
    #expect(try encoder.encode(pcmBytes: halfFrame).count == 1)
}

// MARK: - Helpers

private func makeSinePCM(
    seconds: Int,
    sampleRate: Int,
    toneHz: Double,
    amplitude: Double
) -> Data {
    let total = seconds * sampleRate
    var data = Data(capacity: total * MemoryLayout<Int16>.size)
    for idx in 0 ..< total {
        let time = Double(idx) / Double(sampleRate)
        let sample = sin(2 * .pi * toneHz * time) * amplitude
        let int16 = Int16(max(-1.0, min(1.0, sample)) * Double(Int16.max))
        var le = int16.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
    return data
}

private func computeRMS(pcm: Data) -> Double {
    let count = pcm.count / MemoryLayout<Int16>.size
    guard count > 0 else {
        return 0
    }
    var sumSq: Double = 0
    pcm.withUnsafeBytes { rawBuf in
        let int16Buf = rawBuf.bindMemory(to: Int16.self)
        for sample in int16Buf {
            let normalized = Double(sample) / Double(Int16.max)
            sumSq += normalized * normalized
        }
    }
    return (sumSq / Double(count)).squareRoot()
}
