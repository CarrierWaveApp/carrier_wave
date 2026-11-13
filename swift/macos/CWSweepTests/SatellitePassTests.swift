import CarrierWaveData
import Foundation
import Testing
@testable import CWSweep

// MARK: - Fixtures

private let issRepeater = SweepTransmitter(
    description: "FM cross-band repeater",
    type: "Transponder",
    mode: "FM",
    kind: .fm,
    uplinkHz: 145_990_000,
    downlinkHz: 437_800_000
)

private let iss = SweepSatellite(
    noradID: 25_544, name: "ISS", detailName: "ZARYA", transmitters: [issRepeater]
)

private func pass(aosOffset: TimeInterval, duration: TimeInterval = 600, now: Date) -> SweepPass {
    SweepPass(
        noradID: 25_544,
        name: "ISS",
        aos: now.addingTimeInterval(aosOffset),
        aosAzimuthDeg: 210,
        peak: now.addingTimeInterval(aosOffset + duration / 2),
        peakAzimuthDeg: 140,
        peakElevationDeg: 62,
        peakRangeKm: 470,
        los: now.addingTimeInterval(aosOffset + duration),
        losAzimuthDeg: 40
    )
}

// MARK: - SweepPass

@Test func passCountdownFormatsMinutesAndSeconds() {
    #expect(SweepPass.countdown(0) == "0:00")
    #expect(SweepPass.countdown(65) == "1:05")
    #expect(SweepPass.countdown(599.9) == "9:59")
    #expect(SweepPass.countdown(-5) == "0:00")
}

@Test func passStateRelativeToNow() {
    let now = Date()
    let active = pass(aosOffset: -120, now: now)
    #expect(active.isActive(at: now))
    #expect(!active.isUpcoming(at: now))
    #expect(abs(active.secondsToLOS(at: now) - 480) < 0.001)
    let later = pass(aosOffset: 900, now: now)
    #expect(later.isUpcoming(at: now))
    #expect(!later.isActive(at: now))
}

// MARK: - Doppler readout

@Test func dopplerReadoutUsesEngineSignConvention() {
    // Approaching (ṙ < 0): downlink heard high, uplink sent low.
    let readout = SatelliteDopplerReadout(transmitter: issRepeater, rangeRateKmPerSec: -7)
    #expect(readout.downlinkShiftHz > 10_000)
    #expect(readout.downlinkShiftHz < 10_400)
    #expect(readout.uplinkShiftHz ?? 0 < -3_300)
    #expect(readout.uplinkShiftHz ?? 0 > -3_500)
    #expect(readout.correctedDownlinkHz == readout.nominalDownlinkHz + readout.downlinkShiftHz)
}

@Test func beaconHasNoUplinkRow() {
    let beacon = SweepTransmitter(
        description: "CW beacon", type: "Transmitter", mode: "CW", kind: .cw,
        uplinkHz: nil, downlinkHz: 145_825_000
    )
    let readout = SatelliteDopplerReadout(transmitter: beacon, rangeRateKmPerSec: 3)
    #expect(readout.nominalUplinkHz == nil)
    #expect(readout.correctedUplinkHz == nil)
    #expect(readout.downlinkShiftHz < 0)
}

@Test func primaryTransmitterPrefersActiveWithDownlink() {
    let dead = SweepTransmitter(
        description: "Old beacon", type: "Transmitter", alive: false, isActive: false,
        mode: "CW", kind: .cw, uplinkHz: nil, downlinkHz: 145_000_000
    )
    #expect(SweepTransmitter.primary(in: [dead, issRepeater]) == issRepeater)
    #expect(SweepTransmitter.primary(in: [dead]) == dead)
    #expect(SweepTransmitter.primary(in: []) == nil)
}

// MARK: - Frame

@Test func frameCountdownsAndSMeter() {
    let now = Date()
    var frame = SatellitePassFrame(now: now)
    frame.pass = pass(aosOffset: -60, now: now)
    frame.satellite = iss
    #expect(frame.isPassActive)
    #expect(abs((frame.secondsToLOS ?? 0) - 540) < 0.001)
    #expect(frame.secondsToAOS == nil)
    #expect(frame.sMeterLabel == "S0")

    frame.look = SatelliteLiveLook(
        at: now, azimuthDeg: 180, elevationDeg: 45, rangeKm: 600,
        rangeRateKmPerSec: -2, azRateDegPerSec: 0.1, elRateDegPerSec: 0.05, altitudeKm: 420
    )
    frame.signalStrength = SatelliteWaterfallSynth.strength(rangeKm: 600)
    #expect(frame.sMeterLabel.hasPrefix("S9"))

    var upcoming = SatellitePassFrame(now: now)
    upcoming.pass = pass(aosOffset: 300, now: now)
    #expect(!upcoming.isPassActive)
    #expect(abs((upcoming.secondsToAOS ?? 0) - 300) < 0.001)
}

@Test func liveLookDeadReckonsAndWrapsAzimuth() {
    let look = SatelliteLiveLook(
        at: Date(), azimuthDeg: 359.5, elevationDeg: 10, rangeKm: 1_000,
        rangeRateKmPerSec: -5, azRateDegPerSec: 1, elRateDegPerSec: 0.5, altitudeKm: nil
    )
    let later = look.advanced(by: 2)
    #expect(abs(later.azimuthDeg - 1.5) < 0.001)
    #expect(abs(later.elevationDeg - 11) < 0.001)
    #expect(abs(later.rangeKm - 990) < 0.001)
}

// MARK: - Waterfall synth

@Test func waterfallSignalSitsAtCorrectedDownlinkWhenUncorrected() {
    let nominal = 437_800_000.0
    let corrected = nominal + 9_000 // approaching, +9 kHz
    let line = SatelliteWaterfallSynth.line(
        centerHz: nominal, signalHz: corrected, widthHz: 10_000, strength: 1, seed: 7
    )
    #expect(line.magnitudes.count == SatelliteWaterfallSynth.defaultBins)
    let peakBin = line.magnitudes.indices.max { line.magnitudes[$0] < line.magnitudes[$1] } ?? 0
    let expectedBin = SatelliteWaterfallSynth.bin(for: corrected, in: line) ?? -1
    // Flat-topped 10 kHz signal → peak somewhere within ±5 kHz of center.
    #expect(abs(Double(peakBin) - expectedBin) * line.binHz <= 5_000)
    // Far edge of the display is just noise.
    #expect(line.magnitudes[0] < 0.25)
    #expect(line.magnitudes[line.magnitudes.count - 1] < 0.25)
}

@Test func waterfallCorrectedViewKeepsSignalCentered() {
    let corrected = 437_809_000.0
    let line = SatelliteWaterfallSynth.line(
        centerHz: corrected, signalHz: corrected, widthHz: 2_400, strength: 0.8, seed: 1
    )
    let center = line.magnitudes.count / 2
    #expect(line.magnitudes[center] > 0.6)
    #expect(line.magnitudes[center - 40] < 0.25)
    #expect(line.magnitudes[center + 40] < 0.25)
}

@Test func waterfallNoiseOnlyBelowHorizon() {
    let line = SatelliteWaterfallSynth.line(
        centerHz: 437_800_000, signalHz: nil, widthHz: 10_000, strength: 0, seed: 3
    )
    #expect(line.magnitudes.allSatisfy { $0 < 0.25 })
    #expect(SatelliteWaterfallSynth.strength(rangeKm: nil) == 0)
    #expect(SatelliteWaterfallSynth.strength(rangeKm: 500) == 1)
    #expect(SatelliteWaterfallSynth.strength(rangeKm: 3_500) == 0)
}

@Test func waterfallIsDeterministicForASeed() {
    let a = SatelliteWaterfallSynth.line(centerHz: 1e8, signalHz: 1e8, widthHz: 300, strength: 0.5, seed: 42)
    let b = SatelliteWaterfallSynth.line(centerHz: 1e8, signalHz: 1e8, widthHz: 300, strength: 0.5, seed: 42)
    #expect(a == b)
}

@Test func signalWidthFollowsMode() {
    #expect(SatelliteWaterfallSynth.signalWidthHz(mode: .fm) == 10_000)
    #expect(SatelliteWaterfallSynth.signalWidthHz(mode: .cw) < SatelliteWaterfallSynth.signalWidthHz(mode: .ssb))
}

// MARK: - Sidebar

@Test func satellitesLivesInTheOperatingSection() {
    #expect(SidebarSection.operating.items.contains(.satellites))
    #expect(SidebarItem.satellites.displayName == "Satellites")
}
