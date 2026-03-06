import Foundation
import Testing
@testable import CWSweep

// MARK: - TuneInStrategy Tests

@Test func tuneInStrategyTitles() {
    #expect(TuneInStrategy.nearStrongRBN.title == "Best signal")
    #expect(TuneInStrategy.nearActivator.title == "Near the activator")
    #expect(TuneInStrategy.nearMyQTH.title == "Near my location")
}

@Test func tuneInStrategyDescriptions() {
    #expect(!TuneInStrategy.nearStrongRBN.description.isEmpty)
    #expect(!TuneInStrategy.nearActivator.description.isEmpty)
    #expect(!TuneInStrategy.nearMyQTH.description.isEmpty)
}

@Test func tuneInStrategySystemImages() {
    #expect(!TuneInStrategy.nearStrongRBN.systemImage.isEmpty)
    #expect(!TuneInStrategy.nearActivator.systemImage.isEmpty)
    #expect(!TuneInStrategy.nearMyQTH.systemImage.isEmpty)
}

@Test func tuneInStrategyCaseIterable() {
    #expect(TuneInStrategy.allCases.count == 3)
}

// MARK: - TuneInSpot Tests

@Test func tuneInSpotProperties() {
    let spot = TuneInSpot(
        callsign: "W1AW",
        frequencyMHz: 14.074,
        mode: "CW",
        band: "20m",
        parkRef: "US-0001",
        parkName: "Yellowstone",
        summitCode: nil,
        summitName: nil,
        latitude: nil,
        longitude: nil,
        grid: "FN31"
    )
    #expect(spot.callsign == "W1AW")
    #expect(spot.frequencyMHz == 14.074)
    #expect(spot.mode == "CW")
    #expect(spot.band == "20m")
    #expect(spot.parkRef == "US-0001")
    #expect(spot.grid == "FN31")
}

// MARK: - TuneInSpotMetadata Tests

@Test func tuneInSpotMetadata() {
    let metadata = TuneInSpotMetadata(
        callsign: "KF7HVM",
        parkRef: "US-0001",
        parkName: "Yellowstone",
        summitCode: nil,
        band: "20m"
    )
    #expect(metadata.callsign == "KF7HVM")
    #expect(metadata.parkRef == "US-0001")
    #expect(metadata.parkName == "Yellowstone")
    #expect(metadata.summitCode == nil)
    #expect(metadata.band == "20m")
}

// MARK: - TuneInManager State Tests

@MainActor
@Test func tuneInManagerInitialState() {
    let manager = TuneInManager()
    #expect(!manager.isActive)
    #expect(manager.spot == nil)
    #expect(manager.qsyAlert == nil)
}
