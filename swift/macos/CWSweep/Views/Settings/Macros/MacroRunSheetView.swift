import CarrierWaveData
import SwiftUI

// MARK: - MacroRunSheetView

/// Run a macro against the connected radio. macOS-flavored variant of
/// the iOS sheet — used by Plan G Task 3's `MacroRunWindowController`
/// as the contents of a separate NSWindow.
///
/// Layout:
/// - Header (spec name + capability chips)
/// - Pre-flight banner (only when safety gate returned a confirmation
///   or refusal reason)
/// - Arg prompts (one row per `RadioMacroArg`)
/// - Big Run / Cancel button
/// - Live log of executor events
/// - Result banner at completion
struct MacroRunSheetView: View {
    // MARK: Lifecycle

    init(
        spec: RadioMacroSpec,
        plan: RadioStatePlan? = nil,
        menuPlanRows: [MenuPlanRow]? = nil
    ) {
        self.spec = spec
        self.plan = plan
        self.menuPlanRows = menuPlanRows
        _model = State(wrappedValue: MacroExecutionModel(
            sinkFactory: { @MainActor in MacRadioSessionMacroSink.live() },
            safetyEnvFactory: { MacroAppSafetyEnvironment() },
            contextProvider: { @MainActor in .preview }
        ))
    }

    // MARK: Internal

    let spec: RadioMacroSpec
    /// Pre-computed plan from a `RadioIntent` resolution. Rendered as a
    /// Terraform-style diff above the args / actions sections so the user
    /// sees exactly what will change before tapping Run.
    let plan: RadioStatePlan?
    /// Pre-computed menu diff rows (current → desired). Snapshotted once
    /// at intent invocation via `MenuReader` since polling menus would
    /// keep the radio in menu mode continuously.
    let menuPlanRows: [MenuPlanRow]?

    var body: some View {
        Form {
            headerSection
            if let safetyDecision = model.safetyDecision {
                safetyBanner(for: safetyDecision)
            }
            if let plan, !plan.actions.isEmpty {
                planSection(plan)
            }
            if let menuPlanRows, !menuPlanRows.isEmpty {
                menuSection(menuPlanRows)
            }
            if !spec.args.isEmpty {
                argsSection
            }
            actionsSection
            if !model.liveLog.isEmpty {
                liveLogSection
            }
            if let outcome = model.outcome {
                outcomeSection(outcome)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Run Macro")
        .task {
            model.seedDefaults(args: spec.args)
            await model.preflight(spec: spec)
        }
    }

    // MARK: Private

    @State private var model: MacroExecutionModel

    private var runDisabled: Bool {
        guard let decision = model.safetyDecision else {
            return true
        }
        if case .refuse = decision.outcome {
            return true
        }
        return false
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: spec.icon ?? "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec.name)
                        .font(.headline)
                    MacroCapabilityChipsCompact(capabilities: spec.capabilities)
                }
                Spacer()
            }
            if let description = spec.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var argsSection: some View {
        Section("Arguments") {
            ForEach(spec.args) { arg in
                MacroArgPromptRow(
                    arg: arg,
                    value: Binding(
                        get: { model.resolvedArgs[arg.name] ?? "" },
                        set: { model.resolvedArgs[arg.name] = $0 }
                    )
                )
            }
        }
    }

    private var actionsSection: some View {
        Section {
            if model.isRunning {
                Button(role: .destructive) {
                    model.cancel()
                } label: {
                    Label("Cancel run", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    Task { await model.run(spec: spec) }
                } label: {
                    Label("Run macro", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.body.weight(.semibold))
                }
                .disabled(runDisabled)
            }
        }
    }

    private var liveLogSection: some View {
        Section("Run log") {
            ForEach(model.liveLog) { entry in
                MacroExecutionLogRow(entry: entry)
            }
        }
    }

    @ViewBuilder
    private func safetyBanner(for decision: MacroSafetyDecision) -> some View {
        switch decision.outcome {
        case .allow:
            EmptyView()
        case let .allowWithConfirmation(reason):
            MacroSafetyConfirmationBanner(reason: reason, tone: .warning)
        case let .refuse(reason):
            MacroSafetyConfirmationBanner(reason: reason, tone: .error)
        }
    }

    private func planSection(_ plan: RadioStatePlan) -> some View {
        Section("Plan") {
            ForEach(Array(plan.actions.enumerated()), id: \.offset) { _, action in
                MacroPlanRow(action: action)
            }
            if !plan.unverifiable.isEmpty {
                Text("\(plan.unverifiable.count) write-only setting(s) can't be verified")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func menuSection(_ rows: [MenuPlanRow]) -> some View {
        Section("Menu") {
            ForEach(rows) { row in
                MenuPlanRowView(row: row)
            }
        }
    }

    private func outcomeSection(_ outcome: MacroExecutionOutcome) -> some View {
        Section {
            MacroOutcomeBanner(outcome: outcome)
        }
    }
}

// MARK: - MacroArgPromptRow

struct MacroArgPromptRow: View {
    let arg: RadioMacroArg

    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(arg.label ?? arg.name)
                .font(.body)
            switch arg.type {
            case .bool:
                Picker("", selection: $value) {
                    Text("true").tag("true")
                    Text("false").tag("false")
                }
                .pickerStyle(.segmented)
            case .uint8,
                 .uint16,
                 .uint32,
                 .uint64,
                 .freqHz,
                 .frequency:
                Stepper(
                    value: Binding(
                        get: { Int(value) ?? 0 },
                        set: { value = String($0) }
                    ),
                    in: (arg.min ?? 0) ... (arg.max ?? .max),
                    step: arg.type == .frequency ? 1_000 : 1
                ) {
                    HStack {
                        TextField("0", text: $value)
                            .multilineTextAlignment(.trailing)
                        Text(arg.type == .frequency ? "Hz" : "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            default:
                TextField("Value", text: $value)
            }
            if let defaultValue = arg.defaultValue {
                Text("Default: \(defaultValue)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - MacroSafetyConfirmationBanner

struct MacroSafetyConfirmationBanner: View {
    // MARK: Internal

    enum Tone {
        case warning
        case error
    }

    let reason: String
    let tone: Tone

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: tone == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(toneColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tone == .error ? "Refused" : "Heads up")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(toneColor)
                    Text(reason)
                        .font(.caption)
                }
            }
        }
        .listRowBackground(toneColor.opacity(0.1))
    }

    // MARK: Private

    private var toneColor: Color {
        switch tone {
        case .warning: .orange
        case .error: .red
        }
    }
}

// MARK: - MacroPlanRow

/// One Terraform-style row of a `RadioStatePlan`. Color encodes intent:
/// gray = already converged, green = field that will change (with the prior
/// value struck through), orange = blind-apply (write-only setting, value
/// shown but no diff because we can't read it back). Values pass through a
/// per-key formatter so `vfoA` shows as MHz and `power` as watts.
struct MacroPlanRow: View {
    // MARK: Internal

    let action: RadioStatePlanAction

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .font(.caption.weight(.semibold))
                .frame(width: 14)
            Text(action.key)
                .font(.callout.monospaced())
                .foregroundStyle(.primary)
                .frame(minWidth: 80, alignment: .leading)
            switch action {
            case let .noChange(_, value):
                Text(format(key: action.key, value: value))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("no change")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            case let .update(_, from, to):
                Text(from.map { format(key: action.key, value: $0) } ?? "—")
                    .font(.callout.monospaced())
                    .foregroundStyle(.red)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(format(key: action.key, value: to))
                    .font(.callout.monospaced())
                    .foregroundStyle(.green)
                Spacer()
            case let .blindApply(_, to):
                Text("→ \(format(key: action.key, value: to))")
                    .font(.callout.monospaced())
                    .foregroundStyle(.orange)
                Spacer()
                Text("write-only")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Private

    private var iconName: String {
        switch action {
        case .noChange: "equal"
        case .update: "arrow.triangle.2.circlepath"
        case .blindApply: "arrow.right.circle"
        }
    }

    private var tint: Color {
        switch action {
        case .noChange: .secondary
        case .update: .green
        case .blindApply: .orange
        }
    }

    /// Map a canonical key/value into a human-friendly representation. Pure
    /// presentation — the planner only ever sees canonical strings.
    private func format(key: String, value: String) -> String {
        switch key {
        case "vfoA":
            if let hz = UInt64(value) {
                return String(format: "%.5f MHz", Double(hz) / 1_000_000)
            }
            return value
        case "power":
            return "\(value) W"
        default:
            return value
        }
    }
}

// MARK: - MacroExecutionLogRow

struct MacroExecutionLogRow: View {
    // MARK: Internal

    let entry: MacroExecutionLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
                .font(.caption.weight(.semibold))
            Text(entry.message)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    private var iconName: String {
        switch entry.kind {
        case .info: "info.circle"
        case .stepStart: "arrow.right"
        case .stepOk: "checkmark"
        case .stepFail: "xmark"
        case .finished: "flag.checkered"
        }
    }

    private var tint: Color {
        switch entry.kind {
        case .info: .secondary
        case .stepStart: .blue
        case .stepOk: .green
        case .stepFail: .red
        case .finished: .green
        }
    }
}

// MARK: - MacroOutcomeBanner

struct MacroOutcomeBanner: View {
    // MARK: Internal

    let outcome: MacroExecutionOutcome

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(tintColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(tintColor)
                Text(message)
                    .font(.caption)
            }
            Spacer()
        }
    }

    // MARK: Private

    private var iconName: String {
        switch outcome {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.octagon.fill"
        case .cancelled: "stop.circle.fill"
        }
    }

    private var tintColor: Color {
        switch outcome {
        case .success: .green
        case .failure: .red
        case .cancelled: .orange
        }
    }

    private var title: String {
        switch outcome {
        case .success: "Macro complete"
        case .failure: "Macro failed"
        case .cancelled: "Cancelled"
        }
    }

    private var message: String {
        switch outcome {
        case let .success(executed, elapsed):
            "Executed \(executed) steps in \(String(format: "%.2f", elapsed)) s"
        case let .failure(reason, stepIndex):
            if let stepIndex {
                "Step \(stepIndex + 1): \(reason)"
            } else {
                reason
            }
        case .cancelled:
            "Run cancelled before completion."
        }
    }
}
