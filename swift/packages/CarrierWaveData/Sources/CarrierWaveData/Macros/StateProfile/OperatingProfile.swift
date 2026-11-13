import Foundation

// MARK: - DataSubMode

/// Elecraft DATA sub-mode. `.none` means the intent doesn't care (used by
/// non-DATA intents) — that case emits no `DT;` set command, so it can't
/// leak across intents. The other cases map 1:1 to KX2/K3 DT codes.
public enum DataSubMode: String, Sendable, Equatable, CaseIterable {
    case none
    case dataA = "data-a"
    case afsk
    case fsk
    case psk

    // MARK: Public

    /// CAT payload for `DT<n>;`. nil for `.none` so the resolution skips it.
    public var ditCode: String? {
        switch self {
        case .none: nil
        case .dataA: "0"
        case .afsk: "1"
        case .fsk: "2"
        case .psk: "3"
        }
    }
}

// MARK: - TxVfo

public enum TxVfo: String, Sendable, Equatable, CaseIterable {
    case a
    case b

    // MARK: Public

    /// CAT payload for `FT<n>;` (Elecraft TX VFO select).
    public var ftCode: String {
        switch self {
        case .a: "0"
        case .b: "1"
        }
    }
}

// MARK: - MenuItem

/// Pair of (KX2/K3 menu item number, target value). Encoded as
/// `MN<item>;MP<value>;` — read-back has no CAT route on the KX2 so menu
/// items are always blind-applied.
public struct MenuItem: Sendable, Equatable {
    // MARK: Lifecycle

    public init(item: UInt16, value: UInt16) {
        self.item = item
        self.value = value
    }

    // MARK: Public

    public let item: UInt16
    public let value: UInt16
}

// MARK: - OperatingProfile

/// The canonical operating-state schema. Every `RadioIntent` produces one of
/// these — every field is required, no optionals on canonical settings.
/// Intents that don't care about a particular field still pick a definite
/// value (e.g. CW intent picks `.none` for `dataSubMode`, false for `vox`).
/// That's the property that closes the cross-intent leakage gap: switching
/// between any two intents writes the full schema, so no setting touched by
/// one intent can persist into another.
///
/// Mapping to the wire happens via `resolution(name:)`, which projects the
/// canonical fields into a `RadioStateProfile` for the planner plus a
/// vendor-command sequence for settings the state model can't express
/// (DATA sub-mode and KX2 menu items).
public struct OperatingProfile: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        vfoAHz: UInt64,
        mode: String,
        powerWatts: UInt8,
        bandwidthHz: UInt16,
        dataSubMode: DataSubMode,
        preamp: Bool,
        attenuator: Bool,
        noiseBlanker: Bool,
        vox: Bool,
        speechCompLevel: UInt8,
        txVfo: TxVfo,
        rit: Bool,
        xit: Bool,
        menuItems: [MenuItem]
    ) {
        self.vfoAHz = vfoAHz
        self.mode = mode
        self.powerWatts = powerWatts
        self.bandwidthHz = bandwidthHz
        self.dataSubMode = dataSubMode
        self.preamp = preamp
        self.attenuator = attenuator
        self.noiseBlanker = noiseBlanker
        self.vox = vox
        self.speechCompLevel = speechCompLevel
        self.txVfo = txVfo
        self.rit = rit
        self.xit = xit
        self.menuItems = menuItems
    }

    // MARK: Public

    public let vfoAHz: UInt64
    public let mode: String
    public let powerWatts: UInt8
    /// Bandwidth in Hz (e.g. 400 for CW, 4000 for FT8). Mapped to the Elecraft
    /// `BW<hh10>;` 4-digit `Hz × 10⁻¹` form by `resolution(name:)`.
    public let bandwidthHz: UInt16
    public let dataSubMode: DataSubMode
    public let preamp: Bool
    public let attenuator: Bool
    public let noiseBlanker: Bool
    public let vox: Bool
    public let speechCompLevel: UInt8
    public let txVfo: TxVfo
    public let rit: Bool
    public let xit: Bool
    public let menuItems: [MenuItem]

    /// Project into the planner inputs: a `RadioStateProfile` keyed on the
    /// canonical field names (matching `RadioStateField.kx2Canonical`) plus
    /// the vendor command sequence + settle delays. Vendor commands always
    /// run after the planned diff because they cover settings with no read
    /// route — `clearRitXit` is the canonical reset action, the menu-item
    /// loop covers KX2 menus 82/128/135, and the DATA sub-mode step only
    /// fires when the intent actually wants a DATA mode.
    public func resolution(name: String) -> RadioIntentResolution {
        let desired: [String: String] = [
            "vfoA": String(vfoAHz),
            "mode": mode,
            "power": String(powerWatts),
            "bandwidth": String(bandwidthHz / 10),
            "preamp": preamp ? "1" : "0",
            "attenuator": attenuator ? "1" : "0",
            "noiseBlanker": noiseBlanker ? "1" : "0",
            "vox": vox ? "1" : "0",
            "speechComp": String(speechCompLevel),
            "txVfo": txVfo.ftCode,
            "rit": rit ? "1" : "0",
            "xit": xit ? "1" : "0",
        ]

        var vendor: [RadioMacroStep] = []
        if let dt = dataSubMode.ditCode {
            vendor.append(.vendorCommand(commandId: "kw.elecraftDataSubMode", args: ["sub": dataSubMode.rawValue]))
            vendor.append(.delay(durationMs: 100))
            // Fallback raw write for radios where the vendor command catalog
            // doesn't know `kw.elecraftDataSubMode` yet.
            vendor.append(.rawBytes(protocol: RadioCommandProtocol.kenwood.rawValue, bytes: "DT\(dt);"))
            vendor.append(.delay(durationMs: 100))
        }
        // Always-reset action: zero out any RIT/XIT offset the prior session
        // left behind, then the typed rit/xit state writes above settle it.
        vendor.append(.vendorCommand(commandId: "kw.clearRitXit", args: nil))
        vendor.append(.delay(durationMs: 100))
        for menu in menuItems {
            vendor.append(.vendorCommand(
                commandId: "kw.elecraftMenuSet",
                args: ["item": String(menu.item), "value": String(menu.value)]
            ))
            vendor.append(.delay(durationMs: 200))
        }

        return RadioIntentResolution(
            profile: RadioStateProfile(name: name, desired: desired),
            vendorSteps: vendor
        )
    }
}
