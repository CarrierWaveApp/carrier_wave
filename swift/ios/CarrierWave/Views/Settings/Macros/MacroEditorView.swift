import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MacroEditorView

/// Full editor for a `RadioMacro`. Header / capabilities / args / steps
/// live in extension files (one per section) to keep this top-level
/// under the 500-line cap. The shared bottom-of-screen banner surfaces
/// verifier issues from `MacroEditorModel`.
struct MacroEditorView: View {
    // MARK: Lifecycle

    init(macro: RadioMacro, isNewlyCreated: Bool) {
        self.macro = macro
        self.isNewlyCreated = isNewlyCreated
        _model = State(wrappedValue: MacroEditorModel(spec: macro.toSpec()))
    }

    // MARK: Internal

    // MARK: Internal — shared editor state

    @Environment(\.modelContext) var ctx
    @Environment(\.dismiss) var dismiss
    @State var model: MacroEditorModel
    @State var showDiscardAlert = false
    @State var addArgDraft: MacroDraftArg?
    @State var editArgTarget: RadioMacroArg?
    @State var addStepPicker = false
    @State var editStepTarget: MacroStepEditTarget?

    let macro: RadioMacro
    let isNewlyCreated: Bool

    var body: some View {
        Form {
            headerSection
            capabilitiesSection
            argsSection
            stepsSection
        }
        .safeAreaInset(edge: .bottom) {
            if !model.issues.isEmpty {
                MacroVerifierIssuesBanner(issues: model.issues)
            }
        }
        .navigationTitle(isNewlyCreated ? "New Macro" : "Edit Macro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("Discard changes?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .sheet(isPresented: $addStepPicker) {
            NavigationStack {
                MacroStepKindPicker(
                    availableCapabilities: model.spec.capabilities,
                    onSelect: { kind in
                        addStep(kind: kind)
                        addStepPicker = false
                    }
                )
            }
        }
        .sheet(item: $editStepTarget) { target in
            NavigationStack {
                MacroStepEditorSheet(
                    step: model.spec.steps[target.index],
                    onSave: { updated in
                        model.spec.steps[target.index] = updated
                        model.markDirty()
                    }
                )
            }
        }
    }

    // MARK: Private

    // MARK: Internal — used by extensions

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if model.dirty {
                    showDiscardAlert = true
                } else {
                    dismiss()
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                save()
            }
            .disabled(!model.canSave || !model.dirty && !isNewlyCreated)
        }
    }

    private func save() {
        let spec = model.spec
        macro.name = spec.name
        macro.icon = spec.icon
        macro.macroDescription = spec.description
        macro.tags = spec.tags ?? []
        macro.appliesTo = spec.appliesTo ?? []
        macro.author = spec.author
        macro.args = spec.args
        macro.steps = spec.steps
        macro.capabilities = spec.capabilities
        macro.updatedAt = Date()
        try? EntityWriteSink.commitUpsert(macro, in: ctx)
        dismiss()
    }
}

// MARK: - MacroVerifierIssuesBanner

/// Bottom-of-editor banner listing verifier issues with severity color
/// coding. Errors block Save; warnings are advisory.
struct MacroVerifierIssuesBanner: View {
    // MARK: Internal

    let issues: [MacroVerifierIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: icon(issue.severity))
                        .foregroundStyle(color(issue.severity))
                        .font(.caption.weight(.semibold))
                    if let stepIndex = issue.stepIndex {
                        Text("**Step \(stepIndex + 1):** \(issue.message)")
                            .font(.caption)
                    } else {
                        Text(issue.message)
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(color(issue.severity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    // MARK: Private

    private func icon(_ severity: MacroVerifierSeverity) -> String {
        switch severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ severity: MacroVerifierSeverity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        }
    }
}
