import CarrierWaveData
import SwiftUI

// MARK: - MacroRunSheetView

/// Run a macro against the connected radio. Layout:
/// - Header (spec name + capability chips)
/// - Pre-flight banner (only when safety gate returned a confirmation
///   or refusal reason)
/// - Arg prompts (one row per `RadioMacroArg`)
/// - Big Run / Cancel button
/// - Live log of executor events
/// - Result banner at completion
struct MacroRunSheetView: View {
    // MARK: Lifecycle

    init(spec: RadioMacroSpec) {
        self.spec = spec
        _model = State(wrappedValue: MacroExecutionModel(
            sinkFactory: { @MainActor in RadioSessionMacroSink.live() },
            safetyEnvFactory: { MacroAppSafetyEnvironment() },
            contextProvider: { @MainActor in .preview }
        ))
    }

    // MARK: Internal

    let spec: RadioMacroSpec

    var body: some View {
        Form {
            headerSection
            if let safetyDecision = model.safetyDecision {
                safetyBanner(for: safetyDecision)
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
        .navigationTitle("Run Macro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    if model.isRunning {
                        model.cancel()
                    }
                    dismiss()
                }
            }
        }
        .task {
            model.seedDefaults(args: spec.args)
            await model.preflight(spec: spec)
        }
        .onChange(of: model.outcome) { _, newOutcome in
            guard let outcome = newOutcome else {
                return
            }
            Task {
                await MacroTelemetryReporter.reportIfOptedIn(spec: spec, outcome: outcome)
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
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
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(arg.type == .frequency ? "Hz" : "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            default:
                TextField("Value", text: $value)
                    .autocorrectionDisabled()
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
