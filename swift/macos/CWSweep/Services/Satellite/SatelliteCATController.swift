import CarrierWaveData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "SatelliteCAT")

// MARK: - SatelliteUplinkTarget

/// Where the pre-corrected uplink goes.
enum SatelliteUplinkTarget: Hashable, Identifiable, Sendable {
    /// Single radio, no satellite mode: the uplink is a readout only.
    case none
    /// A second radio on its own slot (two-radio full duplex).
    case radio(RadioSlot)
    /// The Sub band of the downlink radio in satellite mode (IC-9700).
    case subBand

    // MARK: Lifecycle

    init?(rawValue: String) {
        switch rawValue {
        case "none": self = .none
        case "subBand": self = .subBand
        default:
            guard rawValue.hasPrefix("radio:"),
                  let slot = RadioSlot(rawValue: String(rawValue.dropFirst("radio:".count)))
            else {
                return nil
            }
            self = .radio(slot)
        }
    }

    // MARK: Internal

    static let allCases: [SatelliteUplinkTarget] = [.none] + RadioSlot.allCases.map { .radio($0) } + [.subBand]

    var id: String {
        rawValue
    }

    var rawValue: String {
        switch self {
        case .none: "none"
        case let .radio(slot): "radio:\(slot.rawValue)"
        case .subBand: "subBand"
        }
    }

    var label: String {
        switch self {
        case .none: "None (readout only)"
        case let .radio(slot): slot.label
        case .subBand: "Sub band of the downlink radio (IC-9700 satellite mode)"
        }
    }

    var shortLabel: String {
        switch self {
        case .none: "—"
        case let .radio(slot): slot.shortLabel
        case .subBand: "Sub"
        }
    }
}

// MARK: - SatelliteCATController

/// Pushes Doppler-corrected frequencies to the radio(s) through
/// `RadioManager` once per second while a pass is in progress.
///
/// - The **downlink slot** (Radio A by default) follows the corrected
///   downlink. On the IC-9700 in satellite mode that is the Main band.
/// - The **uplink target** follows the pre-corrected uplink: a second radio,
///   or the IC-9700's Sub band (`RadioManager+Duplex`), or nothing.
/// - On linear transponders the operator's dial moves are read back and
///   folded into a passband offset (`SatelliteDialFollower`), so the uplink
///   tracks the downlink — reversed on inverting birds.
///
/// Frequencies are rounded to 10 Hz and re-sent only when they move past the
/// deadband, so radios that write EEPROM per set aren't hammered. The uplink
/// keeps being tuned while transmitting: full duplex means the uplink must
/// stay on frequency for the whole over.
@MainActor
@Observable
final class SatelliteCATController {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Keys.enabled)
        downlinkSlot = defaults.string(forKey: Keys.downlinkSlot).flatMap(RadioSlot.init(rawValue:)) ?? .a
        if let stored = defaults.string(forKey: Keys.uplinkTarget).flatMap(SatelliteUplinkTarget.init(rawValue:)) {
            uplinkTarget = stored
        } else if let legacy = defaults.string(forKey: Keys.legacyUplinkSlot).flatMap(RadioSlot.init(rawValue:)) {
            uplinkTarget = .radio(legacy)
        } else {
            uplinkTarget = .none
        }
    }

    // MARK: Internal

    enum LinkState: Equatable {
        case off
        case noRadio
        /// Below the horizon: linked but holding.
        case standby
        case following
        case error(String)

        // MARK: Internal

        var label: String {
            switch self {
            case .off: "CAT off"
            case .noRadio: "No radio"
            case .standby: "CAT armed"
            case .following: "CAT tracking"
            case let .error(message): "CAT: \(message)"
            }
        }
    }

    static let deadbandHz = 20.0

    private(set) var linkState: LinkState = .off
    private(set) var lastCommandedRxHz: Double?
    private(set) var lastCommandedTxHz: Double?
    private(set) var lastSentAt: Date?
    /// True while this controller holds the IC-9700 in satellite mode.
    private(set) var satelliteModeArmed = false

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if !isEnabled {
                linkState = .off
                clearCommanded()
            }
        }
    }

    var downlinkSlot: RadioSlot {
        didSet {
            defaults.set(downlinkSlot.rawValue, forKey: Keys.downlinkSlot)
            preparedKey = nil
        }
    }

    var uplinkTarget: SatelliteUplinkTarget {
        didSet {
            defaults.set(uplinkTarget.rawValue, forKey: Keys.uplinkTarget)
            preparedKey = nil
        }
    }

    /// Operator's position inside a linear passband (Hz from the low edge).
    var dialOffsetHz: Double {
        follower.offsetHz
    }

    var isDuplex: Bool {
        uplinkTarget != .none
    }

    /// One line for the status bar, e.g. "CAT A 437.8030 MHz ⇅ Sub".
    var summaryLabel: String {
        switch linkState {
        case .following:
            guard let rx = lastCommandedRxHz else {
                return linkState.label
            }
            let base = String(format: "CAT %@ %.4f MHz", downlinkSlot.shortLabel, rx / 1_000_000)
            return lastCommandedTxHz == nil ? base : "\(base) ⇅ \(uplinkTarget.shortLabel)"
        default:
            return linkState.label
        }
    }

    /// Apply one frame. Called by `SatellitePassModel` every tick, enabled
    /// or not, so disarming can restore the radio.
    func apply(frame: SatellitePassFrame, radioManager: RadioManager) async {
        guard isEnabled else {
            linkState = .off
            await disarmIfNeeded(radioManager: radioManager)
            return
        }
        guard radioManager.isConnected, radioManager.slots[downlinkSlot] != nil else {
            linkState = .noRadio
            satelliteModeArmed = false
            preparedKey = nil
            return
        }
        guard let transmitter = frame.transmitter, let look = frame.look, look.isAboveHorizon else {
            linkState = .standby
            return
        }
        let key = "\(frame.satellite?.noradID ?? 0)|\(downlinkSlot.rawValue)|\(uplinkTarget.rawValue)"
        if preparedKey != key {
            guard await prepare(transmitter: transmitter, look: look, radioManager: radioManager) else {
                return
            }
            preparedKey = key
        }
        let now = frame.now
        var readout = SatelliteDopplerReadout(
            transmitter: transmitter, rangeRateKmPerSec: look.rangeRateKmPerSec, dialOffsetHz: follower.offsetHz
        )
        if let rigMHz = radioManager.slotStates[downlinkSlot]?.frequency, rigMHz > 0,
           follower.observe(
               rigHz: rigMHz * 1_000_000, at: now, rangeRateKmPerSec: look.rangeRateKmPerSec, transmitter: transmitter
           )
        {
            let offsetHz = follower.offsetHz
            logger.info("dial moved: passband offset now \(offsetHz, privacy: .public) Hz")
            readout = SatelliteDopplerReadout(
                transmitter: transmitter, rangeRateKmPerSec: look.rangeRateKmPerSec, dialOffsetHz: follower.offsetHz
            )
        }
        guard await tuneDownlink(readout.correctedDownlinkHz, at: now, radioManager: radioManager) else {
            return
        }
        await tuneUplink(readout.correctedUplinkHz, radioManager: radioManager)
    }

    // MARK: Private

    private enum Keys {
        static let enabled = "satellite.catEnabled"
        static let downlinkSlot = "satellite.catDownlinkSlot"
        static let uplinkTarget = "satellite.catUplinkTarget"
        static let legacyUplinkSlot = "satellite.catUplinkSlot"
    }

    private let defaults: UserDefaults
    private var preparedKey: String?
    private var follower = SatelliteDialFollower()

    private func clearCommanded() {
        lastCommandedRxHz = nil
        lastCommandedTxHz = nil
        preparedKey = nil
        follower.reset()
    }

    /// Once per satellite / slot assignment: satellite mode (if Sub band),
    /// then modes on both sides.
    private func prepare(transmitter: SweepTransmitter, look: SatelliteLiveLook,
                         radioManager: RadioManager) async -> Bool
    {
        clearCommanded()
        if uplinkTarget == .subBand {
            guard radioManager.supportsSubBandDuplex(slot: downlinkSlot) else {
                linkState = .error("\(downlinkSlot.shortLabel) is not an IC-9700")
                return false
            }
            guard await radioManager.enterSatelliteMode(slot: downlinkSlot) else {
                linkState = .error("satellite mode refused")
                return false
            }
            satelliteModeArmed = true
        }
        await radioManager.setMode(transmitter.kind.radioMode, slot: downlinkSlot)
        switch uplinkTarget {
        case .none:
            break
        case let .radio(slot):
            if radioManager.slots[slot] != nil {
                await radioManager.setMode(transmitter.kind.uplinkRadioMode, slot: slot)
            }
        case .subBand:
            // Mode rides along with the first Sub tune so the sequence runs once.
            let readout = SatelliteDopplerReadout(transmitter: transmitter, rangeRateKmPerSec: look.rangeRateKmPerSec)
            if let txHz = readout.correctedUplinkHz {
                let tx = Double(SatelliteDoppler.roundedHz(txHz))
                if await radioManager.tuneSubBand(
                    frequencyHz: tx,
                    mode: transmitter.kind.uplinkRadioMode,
                    slot: downlinkSlot
                ) {
                    lastCommandedTxHz = tx
                }
            }
        }
        return true
    }

    private func tuneDownlink(_ hz: Double, at now: Date, radioManager: RadioManager) async -> Bool {
        let rx = Double(SatelliteDoppler.roundedHz(hz))
        guard lastCommandedRxHz.map({ abs($0 - rx) >= Self.deadbandHz }) ?? true else {
            linkState = .following
            return true
        }
        guard await radioManager.tuneToFrequency(rx / 1_000_000, slot: downlinkSlot) else {
            linkState = .error("downlink tune failed")
            return false
        }
        lastCommandedRxHz = rx
        lastSentAt = now
        follower.noteCommanded(rxHz: rx, at: now)
        linkState = .following
        return true
    }

    private func tuneUplink(_ hz: Double?, radioManager: RadioManager) async {
        guard let hz else {
            return
        }
        let tx = Double(SatelliteDoppler.roundedHz(hz))
        guard lastCommandedTxHz.map({ abs($0 - tx) >= Self.deadbandHz }) ?? true else {
            return
        }
        let ok: Bool
        switch uplinkTarget {
        case .none:
            return
        case let .radio(slot):
            guard radioManager.slots[slot] != nil else {
                return
            }
            ok = await radioManager.tuneToFrequency(tx / 1_000_000, slot: slot)
        case .subBand:
            ok = await radioManager.tuneSubBand(frequencyHz: tx, mode: nil, slot: downlinkSlot)
        }
        if ok {
            lastCommandedTxHz = tx
        } else {
            linkState = .error("uplink tune failed")
        }
    }

    private func disarmIfNeeded(radioManager: RadioManager) async {
        guard satelliteModeArmed else {
            return
        }
        satelliteModeArmed = false
        await radioManager.restoreSatelliteMode(slot: downlinkSlot)
    }
}
