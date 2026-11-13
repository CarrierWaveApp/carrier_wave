import Foundation

// MARK: - MacroSafetyDecision

/// Outcome of running the pre-run safety pipeline against a macro + a set of
/// resolved arguments + a live environment snapshot. The executor consults
/// this before dispatching the first step.
public struct MacroSafetyDecision: Sendable, Equatable {
    // MARK: Lifecycle

    public init(outcome: Outcome, postSubstitutionFreqIssues: [String]) {
        self.outcome = outcome
        self.postSubstitutionFreqIssues = postSubstitutionFreqIssues
    }

    // MARK: Public

    public enum Outcome: Sendable, Equatable {
        case allow
        case allowWithConfirmation(reason: String)
        case refuse(reason: String)
    }

    public let outcome: Outcome
    /// Per-arg diagnostics from the post-substitution band-plan check. Empty
    /// unless the band-plan gate fired. Populated even on refusal so the
    /// caller can surface every offending arg, not just the headline.
    public let postSubstitutionFreqIssues: [String]
}

// MARK: - MacroSafetyEnvironment

/// Async-readable environment snapshot the safety gate consults. The
/// production wiring (an executor wrapper inside the app) implements this
/// against `RadioService`, user settings, and the current region preference.
/// Async so callers don't have to cache values that might be expensive to
/// derive synchronously (e.g. peeking at a `MainActor` service from a
/// background dispatch).
public protocol MacroSafetyEnvironment: Sendable {
    var connectedProtocol: RadioCommandProtocol? { get async }
    var sessionAllowsTx: Bool { get async }
    var globalInhibitTx: Bool { get async }
    var deviceRegion: String { get async }
}

// MARK: - MacroSafetyGate

/// Pre-run safety pipeline. The executor calls
/// `MacroSafetyGate.evaluate(...)` before dispatching the first step. The
/// pipeline returns one of `.allow`, `.allowWithConfirmation`, or
/// `.refuse`; in Phase 1, refusals are not user-overridable.
///
/// Order matters — earlier gates short-circuit later ones:
/// 1. Verifier re-check (capability-lying, missing bounds, etc.)
/// 2. Protocol mismatch against the connected radio (confirmation, not refusal)
/// 3. Post-substitution band-plan check on resolved frequency args
/// 4. TX policy (global inhibit refusal; per-session arm confirmation)
public enum MacroSafetyGate {
    // MARK: Public

    public static func evaluate(
        spec: RadioMacroSpec,
        resolvedArgs: [String: String],
        environment: any MacroSafetyEnvironment
    ) async -> MacroSafetyDecision {
        if let verifierDecision = checkVerifier(spec: spec) {
            return verifierDecision
        }

        let connected = await environment.connectedProtocol
        let region = await environment.deviceRegion
        let inhibitTx = await environment.globalInhibitTx
        let sessionAllowsTx = await environment.sessionAllowsTx

        if let mismatch = checkProtocol(spec: spec, connected: connected) {
            return mismatch
        }
        if let bandIssue = checkBandPlan(
            spec: spec,
            resolvedArgs: resolvedArgs,
            region: region
        ) {
            return bandIssue
        }
        if let txDecision = checkTx(
            spec: spec,
            globalInhibitTx: inhibitTx,
            sessionAllowsTx: sessionAllowsTx
        ) {
            return txDecision
        }
        return MacroSafetyDecision(outcome: .allow, postSubstitutionFreqIssues: [])
    }

    // MARK: Private

    private static func checkVerifier(spec: RadioMacroSpec) -> MacroSafetyDecision? {
        let issues = MacroVerifier.verify(spec)
        if let firstError = issues.first(where: { $0.severity == .error }) {
            return MacroSafetyDecision(
                outcome: .refuse(reason: firstError.message),
                postSubstitutionFreqIssues: []
            )
        }
        return nil
    }

    private static func checkProtocol(
        spec: RadioMacroSpec,
        connected: RadioCommandProtocol?
    ) -> MacroSafetyDecision? {
        guard
            let connected,
            let applies = spec.appliesTo,
            !applies.isEmpty,
            !applies.contains(connected)
        else {
            return nil
        }
        let appliesList = applies.map(\.rawValue).joined(separator: ", ")
        let reason = "Macro is for \(appliesList) but connected radio is \(connected.rawValue)"
        return MacroSafetyDecision(
            outcome: .allowWithConfirmation(reason: reason),
            postSubstitutionFreqIssues: []
        )
    }

    private static func checkBandPlan(
        spec: RadioMacroSpec,
        resolvedArgs: [String: String],
        region: String
    ) -> MacroSafetyDecision? {
        let freqArgs = spec.args.filter { $0.type == .frequency || $0.type == .freqHz }
        guard !freqArgs.isEmpty else {
            return nil
        }
        let plan = BandPlan.load(region: region)
        var failures: [String] = []
        for arg in freqArgs {
            guard
                let raw = resolvedArgs["arg.\(arg.name)"],
                let hertz = UInt64(raw)
            else {
                continue
            }
            if !plan.allowsTx(at: hertz) {
                failures.append("\(arg.name)=\(hertz) Hz")
            }
        }
        guard !failures.isEmpty else {
            return nil
        }
        let reason = "Frequency outside \(region) band plan: \(failures.joined(separator: ", "))"
        return MacroSafetyDecision(
            outcome: .refuse(reason: reason),
            postSubstitutionFreqIssues: failures
        )
    }

    private static func checkTx(
        spec: RadioMacroSpec,
        globalInhibitTx: Bool,
        sessionAllowsTx: Bool
    ) -> MacroSafetyDecision? {
        guard spec.capabilities.transmits else {
            return nil
        }
        if globalInhibitTx {
            return MacroSafetyDecision(
                outcome: .refuse(reason: "Inhibit Transmit is enabled"),
                postSubstitutionFreqIssues: []
            )
        }
        if !sessionAllowsTx {
            return MacroSafetyDecision(
                outcome: .allowWithConfirmation(
                    reason: "Macro transmits — confirm PTT armed"
                ),
                postSubstitutionFreqIssues: []
            )
        }
        return nil
    }
}
