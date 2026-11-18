import Foundation
import Testing
@testable import CWSweep

// MARK: - RadioBandStepTests

@MainActor
struct RadioBandStepTests {
    @Test func hfRadioStopsAtSixMeters() {
        let manager = RadioManager()
        #expect(manager.nextBandFrequency(from: 28.030, up: true) == 50.030)
        #expect(manager.nextBandFrequency(from: 50.030, up: true) == 1.840) // wraps, no 2m
    }

    @Test func ic9700StepsTwoSeventyTwentyThree() throws {
        let manager = RadioManager()
        let model = try #require(RadioModel.knownModels.first { $0.id == "ic9700-lan" })
        let profile = RadioProfile.fromIcomWiFi(model: model, host: "192.0.2.1", username: "u", password: "p")
        _ = manager.registerSlotState(sessionId: UUID(), profile: profile, portPath: nil)
        #expect(manager.nextBandFrequency(from: 146.520, up: true) == 432.100)
        #expect(manager.nextBandFrequency(from: 432.100, up: true) == 1_296.100)
        #expect(manager.nextBandFrequency(from: 1_296.100, up: true) == 144.200)
        #expect(manager.nextBandFrequency(from: 432.100, up: false) == 144.200)
    }

    @Test func stepTableIsAscending() {
        let mhz = RadioManager.bandStepFrequencies.map(\.mhz)
        #expect(mhz == mhz.sorted())
    }
}
