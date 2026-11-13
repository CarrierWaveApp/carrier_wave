import CarrierWaveData
import Foundation

// MARK: - SatelliteDialFollower

/// Linear-transponder dial following ("transparent tuning").
///
/// On a linear bird the operator spins the downlink dial to find a station
/// or a clear spot. The CAT controller commands Doppler-corrected
/// frequencies, so any readback that is not one of the values we recently
/// sent is a dial move. This struct turns such readbacks into an offset into
/// the transponder passband (relative to the downlink low edge); the
/// uplink then follows the same offset, reversed on inverting transponders
/// (`SatelliteDopplerReadout` does that arithmetic).
///
/// Pure value type so the rules are unit-testable without a radio:
/// - readbacks are ignored until `settleTime` after arming, because the
///   poll loop may still deliver the pre-arm frequency;
/// - a readback within `echoToleranceHz` of any of the last few commanded
///   values is the radio echoing us, not a move;
/// - a readback outside the (corrected) passband plus `passbandMarginHz` is
///   rejected — e.g. a `03` reply that landed on the Sub band;
/// - the resulting offset is clamped to the passband when its width is known.
struct SatelliteDialFollower: Equatable, Sendable {
    // MARK: Internal

    static let echoToleranceHz = 15.0
    static let settleTime: TimeInterval = 2
    static let passbandMarginHz = 5_000.0
    /// Plausibility window when SatNOGS has no upper edge for the transponder.
    static let unknownPassbandHz = 100_000.0
    static let rememberedCommands = 4

    private(set) var offsetHz: Double = 0
    private(set) var armedAt: Date?

    /// Forget everything (new satellite, CAT re-armed).
    mutating func reset() {
        offsetHz = 0
        armedAt = nil
        recentCommandedRxHz.removeAll()
    }

    /// Record a downlink frequency the controller just sent.
    mutating func noteCommanded(rxHz: Double, at now: Date) {
        if armedAt == nil {
            armedAt = now
        }
        recentCommandedRxHz.append(rxHz)
        if recentCommandedRxHz.count > Self.rememberedCommands {
            recentCommandedRxHz.removeFirst(recentCommandedRxHz.count - Self.rememberedCommands)
        }
    }

    /// Interpret a rig readback. Returns true when the operator moved the
    /// dial and `offsetHz` changed.
    mutating func observe(
        rigHz: Double,
        at now: Date,
        rangeRateKmPerSec: Double,
        transmitter: SweepTransmitter
    ) -> Bool {
        guard transmitter.supportsDialFollowing,
              let downLow = transmitter.downlinkHz,
              let armedAt, now.timeIntervalSince(armedAt) >= Self.settleTime,
              !recentCommandedRxHz.isEmpty,
              rigHz > 0
        else {
            return false
        }
        if recentCommandedRxHz.contains(where: { abs($0 - rigHz) <= Self.echoToleranceHz }) {
            return false
        }
        // Undo Doppler to find where in the passband the operator landed.
        let factor = 1 - rangeRateKmPerSec / SatelliteDoppler.lightSpeedKmPerSec
        let nominalHz = rigHz / factor
        let width = transmitter.downlinkPassbandHz ?? Self.unknownPassbandHz
        let candidate = nominalHz - downLow
        guard candidate >= -Self.passbandMarginHz, candidate <= width + Self.passbandMarginHz else {
            return false
        }
        let clamped = transmitter.downlinkPassbandHz == nil ? candidate : min(max(candidate, 0), width)
        offsetHz = clamped
        // The rig now sits where the operator put it; treat that as commanded
        // so the same readback is quiet until the next Doppler step.
        recentCommandedRxHz = [rigHz]
        return true
    }

    // MARK: Private

    private var recentCommandedRxHz: [Double] = []
}
