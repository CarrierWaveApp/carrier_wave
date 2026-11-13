import Foundation
import Testing
@testable import CWSweep

// MARK: - WaterfallStore exclusivity

@MainActor
@Test func waterfallStoreExclusiveSourceBlocksOtherProducers() {
    let store = WaterfallStore()
    store.append(line: [0.5], centerMHz: 14, spanKHz: 100, source: .sculan10)
    store.setExclusiveSource(.sdr)
    #expect(store.magnitudes.isEmpty)

    store.append(line: [0.1], centerMHz: 14, spanKHz: 100, source: .sculan10)
    store.setReceiving(true, source: .flex)
    #expect(store.magnitudes.isEmpty)
    #expect(!store.isReceiving)

    store.append(line: [0.2], centerMHz: 7, spanKHz: 96, source: .sdr)
    store.clear(producer: .sculan10)
    #expect(store.magnitudes == [[0.2]])
    #expect(store.source == .sdr)

    store.setExclusiveSource(nil)
    store.append(line: [0.3], centerMHz: 14, spanKHz: 100, source: .flex)
    #expect(store.magnitudes.count == 2)
}

// MARK: - Calibration peak search

@Test func peakOffsetFindsStrongestBinNearCenter() {
    var line = [Float](repeating: 0.1, count: 100)
    line[60] = 0.9 // +10.5 bins from center → +10.5 kHz at 1 kHz/bin: outside ±5 kHz
    line[53] = 0.7 // +3.5 kHz
    let offset = IQPanadapterService.peakOffsetHz(line: line, spanHz: 100_000)
    #expect(offset == 3_500)
    #expect(IQPanadapterService.peakOffsetHz(line: [], spanHz: 1_000) == nil)
}

@Test func calibrationKeysAreCaseInsensitive() {
    var settings = SDRInputSettings()
    settings.calibrationHzByMode["CW"] = 650
    #expect(settings.calibrationHz(forMode: " cw ") == 650)
    #expect(settings.calibrationHz(forMode: "USB") == 0)
}

@Test func k3PresetSelectsInvertedIFTap() {
    var settings = SDRInputSettings()
    settings.tuningKind = .directRF
    settings.ifInverted = false
    settings.applyK3Preset()
    #expect(settings.tuningKind == .ifTap)
    #expect(settings.ifHz == 8_215_000)
    #expect(settings.ifInverted)
}

// MARK: - End to end through the Rust pipeline

@MainActor
@Test func toneSourceStreamsVFOCenteredLinesIntoStore() async throws {
    let suite = "SDRPanadapterTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = WaterfallStore()
    let service = IQPanadapterService(store: store, defaults: defaults)
    var settings = SDRInputSettings()
    settings.enabled = true
    settings.sourceKind = .tone
    settings.sampleRate = 192_000
    settings.spanHz = 48_000
    service.apply(settings)
    service.updateTuning(frequencyMHz: 14.03, mode: "cw", ritHz: 0, ritEnabled: false, transmitting: false)

    for _ in 0 ..< 200 where store.magnitudes.count < 3 {
        try await Task.sleep(for: .milliseconds(25))
    }
    #expect(store.magnitudes.count >= 3)
    #expect(store.source == .sdr)
    #expect(service.status == .running)
    #expect(abs(store.centerFrequencyMHz - 14.03) < 1e-9)
    #expect(store.spanKHz == 48)

    // One test tone sits exactly on the IF → under the VFO (center bin).
    let line = try #require(store.magnitudes.first)
    let offset = try #require(IQPanadapterService.peakOffsetHz(line: line, spanHz: 48_000, searchHz: 1_000))
    #expect(abs(offset) < 100)

    var disabled = settings
    disabled.enabled = false
    service.apply(disabled)
    #expect(service.status == .off)
    #expect(store.exclusiveSource == nil)
    #expect(SDRInputSettings.load(from: defaults) == disabled)
}
