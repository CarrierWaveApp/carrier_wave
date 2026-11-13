import Foundation

// MARK: - MacroExecutionLogEntry

/// Single line in the run-sheet's live log. The view formats arrows /
/// checkmarks based on `kind`.
public struct MacroExecutionLogEntry: Sendable, Identifiable, Equatable {
    // MARK: Lifecycle

    public init(id: UUID = UUID(), kind: Kind, message: String, at: Date = Date()) {
        self.id = id
        self.kind = kind
        self.message = message
        self.at = at
    }

    // MARK: Public

    public enum Kind: Sendable, Equatable {
        case info
        case stepStart
        case stepOk
        case stepFail
        case finished
    }

    public let id: UUID
    public let kind: Kind
    public let message: String
    public let at: Date
}

// MARK: - MacroExecutionOutcome

/// Terminal state of a single run, surfaced to the run sheet.
public enum MacroExecutionOutcome: Sendable, Equatable {
    case success(executed: Int, elapsed: TimeInterval)
    case failure(reason: String, stepIndex: Int?)
    case cancelled
}

// MARK: - MacroExecutionModel

/// View-model for `MacroRunSheetView`. Holds the arg form state, the
/// executor + sink, and the live log buffer. The view binds `resolvedArgs`
/// to the arg-prompt rows and observes `liveLog` / `outcome` for state.
///
/// The model is intentionally sink-agnostic — production wires a
/// `RadioSessionMacroSink`, tests wire a recording mock. The `safetyEnv`
/// closure is async so it can hop to `@MainActor` to peek at
/// `RadioService` without making the model main-actor-only on construction.
@Observable
@MainActor
public final class MacroExecutionModel {
    // MARK: Lifecycle

    public init(
        executor: MacroExecutor = MacroExecutor(),
        sinkFactory: @escaping @Sendable () async -> any MacroExecutorSink,
        safetyEnvFactory: @escaping @Sendable () async -> any MacroSafetyEnvironment,
        contextProvider: @escaping @Sendable @MainActor () -> MacroContext = { .preview }
    ) {
        self.executor = executor
        self.sinkFactory = sinkFactory
        self.safetyEnvFactory = safetyEnvFactory
        self.contextProvider = contextProvider
    }

    // MARK: Public

    public var liveLog: [MacroExecutionLogEntry] = []
    public var resolvedArgs: [String: String] = [:]
    public var isRunning: Bool = false
    public var outcome: MacroExecutionOutcome?
    public var safetyDecision: MacroSafetyDecision?

    /// Pre-evaluate the safety gate so the run sheet can show the pre-flight
    /// banner before the user taps Run. Returns the same decision stored on
    /// `safetyDecision`.
    @discardableResult
    public func preflight(spec: RadioMacroSpec) async -> MacroSafetyDecision {
        let env = await safetyEnvFactory()
        let resolved = templatedArgsForSafety()
        let decision = await MacroSafetyGate.evaluate(
            spec: spec,
            resolvedArgs: resolved,
            environment: env
        )
        safetyDecision = decision
        return decision
    }

    /// Seed `resolvedArgs` with each arg's `defaultValue` if present and the
    /// user hasn't already typed one. Idempotent — safe to call on every
    /// sheet appearance.
    public func seedDefaults(args: [RadioMacroArg]) {
        for arg in args where resolvedArgs[arg.name] == nil {
            if let defaultValue = arg.defaultValue {
                resolvedArgs[arg.name] = defaultValue
            }
        }
    }

    /// Drive the executor. Refuses if the safety gate returned `.refuse`;
    /// proceeds for `.allow` or `.allowWithConfirmation` (the view is
    /// responsible for surfacing confirmation before calling `run`).
    public func run(spec: RadioMacroSpec) async {
        guard !isRunning else {
            return
        }
        isRunning = true
        liveLog.removeAll()
        outcome = nil

        let decision: MacroSafetyDecision = if let safetyDecision {
            safetyDecision
        } else {
            await preflight(spec: spec)
        }
        if case let .refuse(reason) = decision.outcome {
            append(.info, "Refused: \(reason)")
            outcome = .failure(reason: reason, stepIndex: nil)
            isRunning = false
            return
        }

        let sink = await sinkFactory()
        let context = contextProvider()
        currentTask = Task<Void, Never> { [weak self] in
            await self?.dispatch(spec: spec, context: context, sink: sink)
        }
        await currentTask?.value
        currentTask = nil
        isRunning = false
    }

    /// Cooperative cancellation. The executor checks `Task.checkCancellation`
    /// between steps, so this triggers a `.cancelled` MacroExecutorError on
    /// the next boundary.
    public func cancel() {
        currentTask?.cancel()
    }

    public func append(_ kind: MacroExecutionLogEntry.Kind, _ message: String) {
        liveLog.append(MacroExecutionLogEntry(kind: kind, message: message))
    }

    // MARK: Private

    private let executor: MacroExecutor
    private let sinkFactory: @Sendable () async -> any MacroExecutorSink
    private let safetyEnvFactory: @Sendable () async -> any MacroSafetyEnvironment
    private let contextProvider: @Sendable @MainActor () -> MacroContext
    private var currentTask: Task<Void, Never>?

    /// Build the `arg.<name>=value` shape that `MacroSafetyGate` expects.
    /// Mirrors the namespacing the executor does internally.
    private func templatedArgsForSafety() -> [String: String] {
        var out: [String: String] = [:]
        for (name, value) in resolvedArgs {
            out["arg.\(name)"] = value
        }
        return out
    }

    private func dispatch(
        spec: RadioMacroSpec,
        context: MacroContext,
        sink: any MacroExecutorSink
    ) async {
        do {
            append(.info, "Running '\(spec.name)' (\(spec.steps.count) steps)")
            let report = try await executor.execute(
                macro: spec,
                context: context,
                runtimeArgs: resolvedArgs,
                sink: sink
            )
            append(.finished, "Completed \(report.executedSteps) of \(spec.steps.count) steps")
            outcome = .success(executed: report.executedSteps, elapsed: report.elapsed)
        } catch let error as MacroExecutorError {
            handle(error: error)
        } catch is CancellationError {
            append(.info, "Cancelled")
            outcome = .cancelled
        } catch {
            append(.stepFail, "Unexpected: \(error.localizedDescription)")
            outcome = .failure(reason: error.localizedDescription, stepIndex: nil)
        }
    }

    private func handle(error: MacroExecutorError) {
        switch error {
        case .cancelled:
            append(.info, "Cancelled")
            outcome = .cancelled
        case let .stepFailed(stepIndex, kind, reason):
            append(.stepFail, "Step \(stepIndex + 1) (\(kind.rawValue)): \(reason)")
            outcome = .failure(reason: reason, stepIndex: stepIndex)
        case let .assertionFailed(message, stepIndex):
            append(.stepFail, "Assert failed at step \(stepIndex + 1): \(message)")
            outcome = .failure(reason: message, stepIndex: stepIndex)
        case let .missingRequiredArg(name):
            append(.stepFail, "Missing arg '\(name)'")
            outcome = .failure(reason: "Missing arg '\(name)'", stepIndex: nil)
        case let .invalidArgValue(name, value, expected):
            append(.stepFail, "Invalid arg '\(name)'=\(value) (expected \(expected))")
            outcome = .failure(
                reason: "Invalid arg '\(name)'", stepIndex: nil
            )
        case let .argOutOfRange(name, value, min, max):
            let bounds = "\(min.map(String.init) ?? "-")…\(max.map(String.init) ?? "-")"
            append(.stepFail, "Arg '\(name)'=\(value) outside \(bounds)")
            outcome = .failure(reason: "'\(name)' out of range", stepIndex: nil)
        case let .protocolMismatch(expected, connected):
            let expectedList = expected.map(\.rawValue).joined(separator: ", ")
            append(.stepFail, "Protocol mismatch: need \(expectedList), connected to \(connected.rawValue)")
            outcome = .failure(reason: "Protocol mismatch", stepIndex: nil)
        case .noRadioConnected:
            append(.stepFail, "No radio connected")
            outcome = .failure(reason: "No radio connected", stepIndex: nil)
        case .missingCIVAddress:
            append(.stepFail, "Missing CI-V address — set rig address in Radio settings")
            outcome = .failure(reason: "Missing CI-V address", stepIndex: nil)
        case let .sinkRefused(label):
            append(.stepFail, "Radio refused: \(label)")
            outcome = .failure(reason: "Radio refused \(label)", stepIndex: nil)
        case let .template(error):
            append(.stepFail, "Template error: \(error)")
            outcome = .failure(reason: "Template error", stepIndex: nil)
        case let .catalog(error):
            append(.stepFail, "Catalog error: \(error)")
            outcome = .failure(reason: "Catalog error", stepIndex: nil)
        case let .format(detail):
            append(.stepFail, "Format error: \(detail)")
            outcome = .failure(reason: "Format error", stepIndex: nil)
        }
    }
}
