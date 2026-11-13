import Foundation

// MARK: - RadioStatePlanError

public enum RadioStatePlanError: Error, Equatable, Sendable {
    case unknownField(key: String)
    case unencodableValue(key: String, value: String)
}

// MARK: - RadioStatePlanner

/// Drives the declarative loop for radio settings:
/// refresh (read current state) → plan (diff vs desired) → compile (emit a
/// `RadioMacroSpec` of only the diffs) → apply (write the changes) →
/// verify (re-plan to confirm convergence).
///
/// Stateless — construct with a field set (the schema) and reuse. IO goes
/// through a `RadioStateGateway`, so the same planner runs against a mock, a
/// raw-CAT transport, or a live `RadioSession`. This is the spike's thesis:
/// a declarative profile reduces to the existing imperative macro engine.
public struct RadioStatePlanner: Sendable {
    // MARK: Lifecycle

    public init(fields: [RadioStateField]) {
        fieldsByKey = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })
    }

    // MARK: Public

    /// Read current values for the readable fields among `keys`. Unreadable
    /// fields and values the gateway can't read are omitted from the result.
    public func refresh(
        keys: [String],
        gateway: RadioStateGateway
    ) async throws -> [String: String] {
        var current: [String: String] = [:]
        for key in keys {
            guard let field = fieldsByKey[key], field.readable else {
                continue
            }
            if let value = try await gateway.currentValue(forKey: key) {
                current[key] = value
            }
        }
        return current
    }

    /// Diff the profile against live radio state.
    public func plan(
        profile: RadioStateProfile,
        gateway: RadioStateGateway
    ) async throws -> RadioStatePlan {
        var actions: [RadioStatePlanAction] = []
        for (key, target) in profile.desired.sorted(by: { $0.key < $1.key }) {
            guard let field = fieldsByKey[key] else {
                throw RadioStatePlanError.unknownField(key: key)
            }
            if !field.readable {
                actions.append(.blindApply(key: key, to: target))
                continue
            }
            let current = try await gateway.currentValue(forKey: key)
            if current == target {
                actions.append(.noChange(key: key, value: target))
            } else {
                actions.append(.update(key: key, from: current, to: target))
            }
        }
        return RadioStatePlan(actions: actions)
    }

    /// Compile a plan's writes into a runnable `RadioMacroSpec`, proving the
    /// declarative profile reduces to the existing engine. One step per
    /// change; settings already converged produce no step.
    public func compile(_ plan: RadioStatePlan, name: String) throws -> RadioMacroSpec {
        var steps: [RadioMacroStep] = []
        for action in plan.changes {
            let command = try setCommand(for: action)
            steps.append(.rawBytes(protocol: RadioCommandProtocol.kenwood.rawValue, bytes: command))
        }
        return RadioMacroSpec(name: name, appliesTo: [.kenwood], steps: steps)
    }

    /// Compile a plan into a `RadioMacroSpec` using typed steps for canonical
    /// fields (`setFrequency` / `setMode` / `setPowerWatts`) instead of raw
    /// bytes, with appropriate post-step settle delays, then append any
    /// `vendorSteps` verbatim. This is the form the intent → confirm → apply
    /// flow needs: the executor's progress UI reports `setFrequency` more
    /// usefully than a hex blob, and the vendor commands carry the menu-item
    /// configuration the state model can't represent.
    public func compile(
        _ plan: RadioStatePlan,
        vendorSteps: [RadioMacroStep],
        name: String,
        icon: String? = nil,
        appliesTo: [RadioCommandProtocol] = [.kenwood],
        capabilities: RadioMacroCapabilities = RadioMacroCapabilities()
    ) throws -> RadioMacroSpec {
        var steps: [RadioMacroStep] = []
        for action in plan.changes {
            try appendChange(action, into: &steps)
        }
        steps.append(contentsOf: vendorSteps)
        // Self-declare: the safety gate refuses when declared caps don't
        // dominate inferred. Our `.rawBytes` payloads for the new canonical
        // fields (BW/PA/RA/NB/CP/FT/RT/XT) aren't in the opcode table, so
        // inference floors at `transmits=true, usesRawBytes=true`. Unioning
        // those with whatever the caller passed lets the macro through the
        // gate while still letting callers add e.g. `changesFrequency=true`
        // overrides for documentation.
        let inferred = MacroVerifier.inferCapabilities(from: steps)
        return RadioMacroSpec(
            id: UUID(),
            name: name,
            icon: icon,
            appliesTo: appliesTo,
            capabilities: capabilities.union(inferred),
            steps: steps
        )
    }

    /// Apply every change in the plan. Returns the keys that failed to write
    /// (e.g. a setting the connected radio can't set over its current link),
    /// so the caller can surface them.
    public func apply(_ plan: RadioStatePlan, gateway: RadioStateGateway) async throws -> [String] {
        var failed: [String] = []
        for action in plan.changes {
            let ok = try await gateway.apply(key: action.key, value: action.target)
            if !ok {
                failed.append(action.key)
            }
        }
        return failed
    }

    /// Re-plan after applying. `plan.isConverged` is true when no readable
    /// setting still diverges.
    public func verify(
        profile: RadioStateProfile,
        gateway: RadioStateGateway
    ) async throws -> RadioStatePlan {
        try await plan(profile: profile, gateway: gateway)
    }

    // MARK: Private

    private let fieldsByKey: [String: RadioStateField]

    private func setCommand(for action: RadioStatePlanAction) throws -> String {
        guard let field = fieldsByKey[action.key] else {
            throw RadioStatePlanError.unknownField(key: action.key)
        }
        guard let command = field.setCommand(for: action.target) else {
            throw RadioStatePlanError.unencodableValue(key: action.key, value: action.target)
        }
        return command
    }

    /// Translate one plan action into a typed step (with settle delay) when
    /// the key is a canonical field the executor understands directly; fall
    /// back to `rawBytes` for arbitrary state-modeled keys.
    private func appendChange(
        _ action: RadioStatePlanAction,
        into steps: inout [RadioMacroStep]
    ) throws {
        switch action.key {
        case "vfoA":
            guard let hz = UInt64(action.target) else {
                throw RadioStatePlanError.unencodableValue(key: action.key, value: action.target)
            }
            steps.append(.setFrequency(hz: hz))
            steps.append(.delay(durationMs: 600))
        case "mode":
            steps.append(.setMode(mode: action.target))
            steps.append(.delay(durationMs: 150))
        case "power":
            guard let watts = UInt64(action.target) else {
                throw RadioStatePlanError.unencodableValue(key: action.key, value: action.target)
            }
            steps.append(.setPowerWatts(watts: watts))
            steps.append(.delay(durationMs: 100))
        default:
            let command = try setCommand(for: action)
            steps.append(.rawBytes(protocol: RadioCommandProtocol.kenwood.rawValue, bytes: command))
            steps.append(.delay(durationMs: 100))
        }
    }
}
