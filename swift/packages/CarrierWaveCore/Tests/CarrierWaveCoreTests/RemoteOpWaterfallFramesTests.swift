import Foundation
import Testing
@testable import CarrierWaveCore

// MARK: - RemoteOpWaterfallFramesTests

struct RemoteOpWaterfallFramesTests {
    @Test("Quantize / dequantize round-trip stays within 1/255")
    func roundTrip() {
        let original: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let bytes = WaterfallLineEvent.quantize(original)
        let restored = WaterfallLineEvent.dequantize(bytes)
        #expect(restored.count == original.count)
        for (lhs, rhs) in zip(original, restored) {
            #expect(abs(lhs - rhs) < 1.0 / 255.0 + 1e-6)
        }
    }

    @Test("Quantize clamps out-of-range floats")
    func clamping() {
        let bytes = WaterfallLineEvent.quantize([-0.5, 0.5, 1.5])
        #expect(bytes.count == 3)
        #expect(bytes[0] == 0)
        #expect(bytes[1] == 127)
        #expect(bytes[2] == 255)
    }

    @Test("WaterfallLineEvent round-trips through framing")
    func waterfallRoundTrip() throws {
        let bins = WaterfallLineEvent.quantize([0.1, 0.5, 0.9])
        let original = RemoteOpFrame.eventWaterfallLine(.init(
            radioID: "abc",
            source: "SmartSDR",
            centerHz: 14_074_000,
            spanHz: 100_000,
            binCount: 3,
            bins: bins,
            sequence: 42,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000.5)
        ))
        let encoded = try RemoteOpFraming.encodeText(original)
        let decoded = try RemoteOpFraming.decode(text: encoded)
        #expect(decoded == original)
    }

    @Test("WaterfallClearedEvent round-trips through framing")
    func clearedRoundTrip() throws {
        let original = RemoteOpFrame.eventWaterfallCleared(.init(
            radioID: "abc",
            timestamp: Date(timeIntervalSince1970: 1_700_000_001)
        ))
        let encoded = try RemoteOpFraming.encodeText(original)
        let decoded = try RemoteOpFraming.decode(text: encoded)
        #expect(decoded == original)
    }

    @Test("Waterfall topic decodes from raw value")
    func topicRawValue() {
        #expect(RemoteOpTopic(rawValue: "radio.waterfall") == .waterfall)
    }
}
