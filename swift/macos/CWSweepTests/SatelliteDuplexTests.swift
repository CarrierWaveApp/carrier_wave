import CarrierWaveData
import Foundation
import Testing
@testable import CWSweep

// MARK: - Fixtures

/// RS-44 style inverting linear transponder: 145.935–145.995 up, 435.610–435.670 down.
private let rs44 = SweepTransmitter(
    description: "Mode V/U Linear Transponder",
    type: "Transponder",
    mode: "SSB",
    kind: .ssb,
    uplinkHz: 145_935_000,
    downlinkHz: 435_610_000,
    uplinkHighHz: 145_995_000,
    downlinkHighHz: 435_670_000,
    invert: true
)

private let nonInverting = SweepTransmitter(
    description: "Mode U/V Linear Transponder",
    type: "Transponder",
    mode: "SSB",
    kind: .ssb,
    uplinkHz: 435_030_000,
    downlinkHz: 145_980_000,
    uplinkHighHz: 435_090_000,
    downlinkHighHz: 146_040_000,
    invert: false
)

private let issRepeater = SweepTransmitter(
    description: "FM cross-band repeater",
    type: "Transponder",
    mode: "FM",
    kind: .fm,
    uplinkHz: 145_990_000,
    downlinkHz: 437_800_000
)

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Arm the follower with one command and jump past the settle window.
private func armed(rxHz: Double = 435_610_000) -> (SatelliteDialFollower, Date) {
    var follower = SatelliteDialFollower()
    follower.noteCommanded(rxHz: rxHz, at: t0)
    return (follower, t0.addingTimeInterval(SatelliteDialFollower.settleTime + 1))
}

/// `observe` is mutating, which the `#expect` macro can't call inline.
private func observe(
    _ follower: inout SatelliteDialFollower,
    rigHz: Double,
    at now: Date,
    rate: Double = 0,
    transmitter: SweepTransmitter = rs44
) -> Bool {
    follower.observe(rigHz: rigHz, at: now, rangeRateKmPerSec: rate, transmitter: transmitter)
}

// MARK: - Doppler readout with a passband offset

@Test func readoutAppliesOffsetToBothLinksRespectingInversion() {
    let inverting = SatelliteDopplerReadout(transmitter: rs44, rangeRateKmPerSec: 0, dialOffsetHz: 20_000)
    #expect(inverting.nominalDownlinkHz == 435_630_000)
    #expect(inverting.nominalUplinkHz == 145_915_000)
    #expect(inverting.isInverting)
    #expect(inverting.dialOffsetHz == 20_000)

    let normal = SatelliteDopplerReadout(transmitter: nonInverting, rangeRateKmPerSec: 0, dialOffsetHz: 20_000)
    #expect(normal.nominalDownlinkHz == 146_000_000)
    #expect(normal.nominalUplinkHz == 435_050_000)
    #expect(!normal.isInverting)
}

@Test func readoutDefaultsToLowEdge() {
    let readout = SatelliteDopplerReadout(transmitter: rs44, rangeRateKmPerSec: -3)
    #expect(readout.dialOffsetHz == 0)
    #expect(readout.nominalDownlinkHz == 435_610_000)
    #expect(readout.downlinkShiftHz > 0)
    #expect(readout.uplinkShiftHz ?? 0 < 0)
}

// MARK: - Dial follower

@Test func followerIgnoresFMBirds() {
    var (follower, now) = armed(rxHz: 437_800_000)
    let moved = observe(&follower, rigHz: 437_812_500, at: now, transmitter: issRepeater)
    #expect(!moved)
    #expect(follower.offsetHz == 0)
    #expect(!issRepeater.supportsDialFollowing)
    #expect(rs44.supportsDialFollowing)
}

@Test func followerWaitsForSettleAndIgnoresEchoes() {
    var follower = SatelliteDialFollower()
    follower.noteCommanded(rxHz: 435_610_000, at: t0)
    // Stale pre-arm readback inside the settle window must not count.
    let early = observe(&follower, rigHz: 435_640_000, at: t0.addingTimeInterval(0.5))
    #expect(!early)
    let later = t0.addingTimeInterval(SatelliteDialFollower.settleTime + 1)
    // Exact echo of the commanded value, and one within the 10 Hz rounding.
    let echo = observe(&follower, rigHz: 435_610_000, at: later)
    let nearEcho = observe(&follower, rigHz: 435_610_008, at: later)
    #expect(!echo)
    #expect(!nearEcho)
    #expect(follower.offsetHz == 0)
}

@Test func followerRemembersRecentCommandsDuringFastDoppler() {
    var follower = SatelliteDialFollower()
    // Near TCA the controller re-sends every tick; the poll may lag a step.
    for step in 0 ..< 4 {
        follower.noteCommanded(rxHz: 435_610_000 + Double(step) * 30, at: t0.addingTimeInterval(Double(step)))
    }
    let now = t0.addingTimeInterval(SatelliteDialFollower.settleTime + 5)
    let lagOne = observe(&follower, rigHz: 435_610_060, at: now)
    let current = observe(&follower, rigHz: 435_610_090, at: now)
    #expect(!lagOne)
    #expect(!current)
}

@Test func followerTurnsDialMoveIntoPassbandOffset() {
    var (follower, now) = armed()
    // Operator tunes 25 kHz up the passband while the bird is approaching.
    let rate = -5.0
    let rigHz = SatelliteDoppler.correctedDownlinkHz(nominalHz: 435_635_000, rangeRateKmPerSec: rate)
    let moved = observe(&follower, rigHz: rigHz, at: now, rate: rate)
    #expect(moved)
    #expect(abs(follower.offsetHz - 25_000) < 1)
    // Same readback again is now the expected position, not a new move.
    let again = observe(&follower, rigHz: rigHz, at: now, rate: rate)
    #expect(!again)

    let readout = SatelliteDopplerReadout(transmitter: rs44, rangeRateKmPerSec: rate, dialOffsetHz: follower.offsetHz)
    #expect(abs((readout.nominalUplinkHz ?? 0) - 145_910_000) < 1)
    #expect(abs(readout.correctedDownlinkHz - rigHz) < 1)
}

@Test func followerRejectsReadbacksOutsideThePassband() {
    var (follower, now) = armed()
    // A `03` reply that landed on the Sub band (2 m uplink) is not a dial move.
    let subBand = observe(&follower, rigHz: 145_950_000, at: now)
    // Way above the passband on the same band: also rejected.
    let farAbove = observe(&follower, rigHz: 435_900_000, at: now)
    #expect(!subBand)
    #expect(!farAbove)
    #expect(follower.offsetHz == 0)
}

@Test func followerClampsToKnownPassband() {
    var (follower, now) = armed()
    // 3 kHz past the upper edge: inside the margin, clamped to the width.
    let high = observe(&follower, rigHz: 435_673_000, at: now)
    #expect(high)
    #expect(follower.offsetHz == 60_000)
    // Just below the low edge clamps to 0.
    let low = observe(&follower, rigHz: 435_608_000, at: now)
    #expect(low)
    #expect(follower.offsetHz == 0)
}

@Test func followerResetForgetsOffsetAndArming() {
    var (follower, now) = armed()
    let moved = observe(&follower, rigHz: 435_640_000, at: now)
    #expect(moved)
    follower.reset()
    #expect(follower.offsetHz == 0)
    #expect(follower.armedAt == nil)
    let afterReset = observe(&follower, rigHz: 435_640_000, at: now)
    #expect(!afterReset)
}

// MARK: - Uplink target persistence

@Test func uplinkTargetRoundTripsThroughRawValue() {
    for target in SatelliteUplinkTarget.allCases {
        #expect(SatelliteUplinkTarget(rawValue: target.rawValue) == target)
    }
    #expect(SatelliteUplinkTarget(rawValue: "radio:b") == .radio(.b))
    #expect(SatelliteUplinkTarget(rawValue: "radio:z") == nil)
    #expect(SatelliteUplinkTarget(rawValue: "bogus") == nil)
}

@MainActor
@Test func controllerMigratesLegacyUplinkSlot() {
    let suite = "SatelliteDuplexTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        Issue.record("could not create defaults suite")
        return
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("b", forKey: "satellite.catUplinkSlot")
    let controller = SatelliteCATController(defaults: defaults)
    #expect(controller.uplinkTarget == .radio(.b))
    controller.uplinkTarget = .subBand
    #expect(defaults.string(forKey: "satellite.catUplinkTarget") == "subBand")
    let reloaded = SatelliteCATController(defaults: defaults)
    #expect(reloaded.uplinkTarget == .subBand)
    #expect(controller.isDuplex)
}
