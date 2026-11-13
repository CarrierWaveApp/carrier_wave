import Foundation

// MARK: - RadioStateProfile

/// Declarative desired-state for a radio: an unordered map of canonical
/// setting key to desired canonical value. This is the "radio-as-code"
/// document. Its imperative counterpart is a `RadioMacroSpec`; a profile
/// compiles down to one (see `RadioStatePlanner`), so the existing macro
/// engine remains the execution substrate.
///
/// Named `RadioStateProfile` to avoid colliding with the existing
/// `RadioConnectionProfile`, which describes *how to connect* (transport,
/// protocol, CI-V address) rather than *operating state*.
public struct RadioStateProfile: Sendable, Equatable {
    // MARK: Lifecycle

    public init(name: String, desired: [String: String]) {
        self.name = name
        self.desired = desired
    }

    // MARK: Public

    public var name: String
    public var desired: [String: String]
}

// MARK: - Built-in profiles

public extension RadioStateProfile {
    /// 20 m QRP CW calling frequency at 5 W. Uses only CAT-reachable,
    /// readable fields so the full plan/verify loop demonstrates on a
    /// serial-connected Kenwood/Elecraft today.
    static let twentyMeterCW = RadioStateProfile(
        name: "20m CW",
        desired: ["vfoA": "14060000", "mode": "CW", "power": "5"]
    )

    /// 20 m SSB at 5 W.
    static let twentyMeterSSB = RadioStateProfile(
        name: "20m SSB",
        desired: ["vfoA": "14285000", "mode": "USB", "power": "5"]
    )

    /// Profiles a UI/command surface can offer out of the box.
    static let builtIns: [RadioStateProfile] = [twentyMeterCW, twentyMeterSSB]

    /// Look up a built-in profile by display name (case-insensitive).
    static func builtIn(named name: String) -> RadioStateProfile? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return builtIns.first { $0.name.lowercased() == key }
    }
}

// MARK: - RadioStatePlanAction

/// One row of a plan, mirroring `terraform plan` output.
public enum RadioStatePlanAction: Sendable, Equatable {
    /// Current value already matches desired — no write needed.
    case noChange(key: String, value: String)
    /// Readable setting that diverges. `from` is nil when the current value
    /// couldn't be read or parsed.
    case update(key: String, from: String?, to: String)
    /// Write-only setting: applied unconditionally because it can't be read,
    /// so divergence can be neither detected nor verified.
    case blindApply(key: String, to: String)

    // MARK: Public

    public var key: String {
        switch self {
        case let .noChange(key, _): key
        case let .update(key, _, _): key
        case let .blindApply(key, _): key
        }
    }

    /// The value this action would drive the setting to.
    public var target: String {
        switch self {
        case let .noChange(_, value): value
        case let .update(_, _, value): value
        case let .blindApply(_, value): value
        }
    }
}

// MARK: - RadioStatePlan

/// The diff between a profile's desired state and the radio's current
/// state. `apply` writes `changes`; convergence is judged on `drift` only,
/// since blind-apply settings can never be confirmed.
public struct RadioStatePlan: Sendable, Equatable {
    // MARK: Lifecycle

    public init(actions: [RadioStatePlanAction]) {
        self.actions = actions
    }

    // MARK: Public

    public let actions: [RadioStatePlanAction]

    /// Readable settings whose current value diverges from desired.
    public var drift: [RadioStatePlanAction] {
        actions.filter { action in
            if case .update = action {
                true
            } else {
                false
            }
        }
    }

    /// Settings that require a write: readable drift plus all write-only
    /// settings (which are always re-applied).
    public var changes: [RadioStatePlanAction] {
        actions.filter { action in
            switch action {
            case .update,
                 .blindApply: true
            case .noChange: false
            }
        }
    }

    /// Keys written blindly that cannot be read back to confirm.
    public var unverifiable: [String] {
        actions.compactMap { action in
            if case let .blindApply(key, _) = action {
                key
            } else {
                nil
            }
        }
    }

    /// True when no readable setting diverges. Blind-apply settings don't
    /// block convergence because they can't be read back.
    public var isConverged: Bool {
        drift.isEmpty
    }
}
