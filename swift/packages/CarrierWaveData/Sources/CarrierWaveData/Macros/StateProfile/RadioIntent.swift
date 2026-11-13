import CarrierWaveCore
import Foundation

// MARK: - RadioIntentContext

/// What the intent resolver needs to know about the radio's current state:
/// where the dial is (so band-aware intents like FT8 jump to the right
/// calling frequency on the current band), what mode the radio is in (for
/// future relative-jump intents), and which CAT protocol family is connected
/// (so vendor command sequences match the rig). Mirrors the inputs the
/// declarative planner already consumes — no fresh IO needed.
public struct RadioIntentContext: Sendable {
    // MARK: Lifecycle

    public init(
        currentFrequencyHz: UInt64?,
        currentMode: String?,
        protocolKind: RadioCommandProtocol
    ) {
        self.currentFrequencyHz = currentFrequencyHz
        self.currentMode = currentMode
        self.protocolKind = protocolKind
    }

    // MARK: Public

    public let currentFrequencyHz: UInt64?
    public let currentMode: String?
    public let protocolKind: RadioCommandProtocol

    /// Band key (e.g. `"20m"`) derived from the current frequency, or nil if
    /// off-band / not connected. Uses `BandUtilities.deriveBand` so all band
    /// math agrees with the rest of the app.
    public var bandKey: String? {
        guard let hz = currentFrequencyHz, hz > 0 else {
            return nil
        }
        return BandUtilities.deriveBand(from: Double(hz) / 1_000)
    }
}

// MARK: - RadioIntentResolution

/// Output of an intent: the target state to converge to (planner.plan +
/// compile material) plus any vendor command steps that aren't in the
/// state model — filter bandwidth, AGC menu items, etc. Vendor steps run
/// unconditionally after the planned diff because they have no readable
/// codec route today.
public struct RadioIntentResolution: Sendable {
    // MARK: Lifecycle

    public init(profile: RadioStateProfile, vendorSteps: [RadioMacroStep]) {
        self.profile = profile
        self.vendorSteps = vendorSteps
    }

    // MARK: Public

    public let profile: RadioStateProfile
    public let vendorSteps: [RadioMacroStep]
}

// MARK: - RadioIntent

/// User-facing operating intent. `"operate FT8"` / `"operate CW"` etc.
/// Resolution is dynamic: the macro the user sees in the confirmation sheet
/// is generated against current state at invocation, not looked up from a
/// library. The static seed macros under `server/seed_macros/` are the
/// expert-knowledge fixtures these definitions are derived from but are NOT
/// the runtime source of truth — see memory `dynamic-radio-macros`.
public enum RadioIntent: String, Sendable, CaseIterable {
    case ft8
    case cw
    case ssb

    // MARK: Public

    public var displayName: String {
        switch self {
        case .ft8: "Operate FT8"
        case .cw: "Operate CW"
        case .ssb: "Operate SSB"
        }
    }

    public var icon: String {
        switch self {
        case .ft8: "waveform.path.ecg"
        case .cw: "dot.radiowaves.left.and.right"
        case .ssb: "waveform"
        }
    }

    /// Resolve to a desired state + vendor sequence for `context`. Returns nil
    /// when the protocol isn't supported yet (e.g. Icom CI-V for FT8 today).
    public func resolve(context: RadioIntentContext) -> RadioIntentResolution? {
        operatingProfile(context: context)?.resolution(name: displayName)
    }

    /// Resolve to the canonical `OperatingProfile`. Lets the runner reach the
    /// declared menu items so they can be diffed against a live snapshot
    /// before the plan opens. Returns nil for unsupported protocols.
    public func operatingProfile(context: RadioIntentContext) -> OperatingProfile? {
        switch (self, context.protocolKind) {
        case (.ft8, .kenwood):
            kx2FT8(context: context)
        case (.cw, .kenwood):
            kx2CW(context: context)
        case (.ssb, .kenwood):
            kx2SSB(context: context)
        default:
            nil
        }
    }

    // MARK: Private

    /// FT8 calling frequencies by band. Hz. Source: ARRL band plans; matches
    /// the freq the seed FT8 macro hard-codes for 20m (14.074 MHz).
    private static func ft8CallingHz(band: String?) -> UInt64? {
        switch band {
        case "160m": 1_840_000
        case "80m": 3_573_000
        case "60m": 5_357_000
        case "40m": 7_074_000
        case "30m": 10_136_000
        case "20m": 14_074_000
        case "17m": 18_100_000
        case "15m": 21_074_000
        case "12m": 24_915_000
        case "10m": 28_074_000
        case "6m": 50_313_000
        case "2m": 144_174_000
        default: nil
        }
    }

    /// QRP CW calling frequencies by band. Hz. 14.060 / 7.030 / etc.
    private static func cwCallingHz(band: String?) -> UInt64? {
        switch band {
        case "160m": 1_810_000
        case "80m": 3_560_000
        case "60m": 5_330_500
        case "40m": 7_030_000
        case "30m": 10_106_000
        case "20m": 14_060_000
        case "17m": 18_086_000
        case "15m": 21_060_000
        case "12m": 24_906_000
        case "10m": 28_060_000
        case "6m": 50_090_000
        case "2m": 144_100_000
        default: nil
        }
    }

    /// Conventional HF sideband: USB ≥ 10 MHz, LSB < 10 MHz. Defaults to USB
    /// if frequency unknown.
    private static func ssbSideband(currentFrequencyHz: UInt64?) -> String {
        guard let hz = currentFrequencyHz, hz > 0 else {
            return "USB"
        }
        return hz >= 10_000_000 ? "USB" : "LSB"
    }

    /// KX2 menu items shared across all KX2 intents: AGC MD is mode-specific
    /// (off for FT8, on for CW/SSB), MIC BIAS and MIC BTN are always
    /// re-asserted so they can't drift between intents.
    private static func kx2SharedMenus(agcMD: UInt16) -> [MenuItem] {
        [
            MenuItem(item: 128, value: agcMD), // AGC MD speed (0 = off, 1 = on)
            MenuItem(item: 135, value: 16), // MIC BIAS
            MenuItem(item: 82, value: 5), // MIC BTN
        ]
    }

    /// KX2 FT8 operating profile. Every canonical field is declared so any
    /// setting changed by another intent gets explicitly overwritten when
    /// the user switches to FT8.
    private func kx2FT8(context: RadioIntentContext) -> OperatingProfile {
        let targetHz = Self.ft8CallingHz(band: context.bandKey) ?? 14_074_000
        return OperatingProfile(
            vfoAHz: targetHz,
            mode: "DATA",
            powerWatts: 5,
            bandwidthHz: 4_000,
            dataSubMode: .dataA,
            preamp: false,
            attenuator: false,
            noiseBlanker: false, // off so NB hits don't masquerade as FT8 decodes
            vox: true,
            speechCompLevel: 0,
            txVfo: .a,
            rit: false,
            xit: false,
            menuItems: Self.kx2SharedMenus(agcMD: 0) // AGC MD off (slow AGC is wrong for FT8)
        )
    }

    /// KX2 CW operating profile. NB is explicitly on and AGC MD is on — both
    /// fix specific leaks from a prior FT8 run.
    private func kx2CW(context: RadioIntentContext) -> OperatingProfile {
        let targetHz = Self.cwCallingHz(band: context.bandKey) ?? 14_060_000
        return OperatingProfile(
            vfoAHz: targetHz,
            mode: "CW",
            powerWatts: 5,
            bandwidthHz: 400,
            dataSubMode: .none,
            preamp: false,
            attenuator: false,
            noiseBlanker: true, // on — opposite of FT8, closes the prior leak
            vox: false,
            speechCompLevel: 0,
            txVfo: .a,
            rit: false,
            xit: false,
            menuItems: Self.kx2SharedMenus(agcMD: 1)
        )
    }

    /// KX2 SSB profile. USB/LSB inferred from the current band; SSB has no
    /// single calling-freq home so vfoA stays put when possible. Still
    /// declares every canonical field — `speechCompLevel: 10` is the
    /// explicit opposite of FT8's 0.
    private func kx2SSB(context: RadioIntentContext) -> OperatingProfile {
        let targetMode = Self.ssbSideband(currentFrequencyHz: context.currentFrequencyHz)
        let targetHz = context.currentFrequencyHz ?? 14_200_000
        return OperatingProfile(
            vfoAHz: targetHz,
            mode: targetMode,
            powerWatts: 10,
            bandwidthHz: 2_700,
            dataSubMode: .none,
            preamp: false,
            attenuator: false,
            noiseBlanker: true,
            vox: false,
            speechCompLevel: 10,
            txVfo: .a,
            rit: false,
            xit: false,
            menuItems: Self.kx2SharedMenus(agcMD: 1)
        )
    }
}
