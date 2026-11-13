import Foundation
import Testing
@testable import CarrierWaveData

/// ISS cross-band repeater: 437.800 MHz down, 145.990 MHz up. At AOS the
/// range rate is about −7 km/s (approaching), at LOS about +7 km/s.
private let issDownlinkHz = 437_800_000.0
private let issUplinkHz = 145_990_000.0

@Test func approachingSatelliteRaisesDownlinkAndLowersUplink() {
    let rr = -7.0
    let rx = SatelliteDoppler.correctedDownlinkHz(nominalHz: issDownlinkHz, rangeRateKmPerSec: rr)
    let tx = SatelliteDoppler.correctedUplinkHz(nominalHz: issUplinkHz, rangeRateKmPerSec: rr)
    #expect(rx > issDownlinkHz)
    #expect(tx < issUplinkHz)
}

@Test func issShiftsMatchTheRuleOfThumb() {
    // ±10 kHz on 70 cm, ±3.3–3.4 kHz on 2 m at |ṙ| ≈ 7 km/s.
    let down = SatelliteDoppler.downlinkShiftHz(nominalHz: issDownlinkHz, rangeRateKmPerSec: 7)
    let up = SatelliteDoppler.uplinkShiftHz(nominalHz: issUplinkHz, rangeRateKmPerSec: 7)
    #expect(abs(down + 10_223) < 20)
    #expect(abs(up - 3_409) < 20)
}

@Test func uplinkCorrectionIsOppositeInSign() {
    for rr in [-6.5, -2.0, 0.0, 3.3, 7.0] {
        let down = SatelliteDoppler.downlinkShiftHz(nominalHz: 435_000_000, rangeRateKmPerSec: rr)
        let up = SatelliteDoppler.uplinkShiftHz(nominalHz: 435_000_000, rangeRateKmPerSec: rr)
        #expect(abs(down + up) < 0.001)
    }
}

@Test func factorMatchesEngineConvention() {
    // Engine: doppler_factor = −ṙ/c; downlink × (1 + f).
    let factor = SatelliteDoppler.factor(rangeRateKmPerSec: -3)
    #expect(factor > 0)
    let viaFactor = issDownlinkHz * (1 + factor)
    let direct = SatelliteDoppler.correctedDownlinkHz(nominalHz: issDownlinkHz, rangeRateKmPerSec: -3)
    #expect(abs(viaFactor - direct) < 0.001)
}

@Test func roundingSnapsToStep() {
    #expect(SatelliteDoppler.roundedHz(437_803_456) == 437_803_460)
    #expect(SatelliteDoppler.roundedHz(437_803_456, stepHz: 100) == 437_803_500)
    #expect(SatelliteDoppler.roundedHz(-5) == 0)
}
