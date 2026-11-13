import CarrierWaveData
import SwiftUI

// MARK: - MacroStepEditTarget

/// Identifies a step in the editor's spec for the edit sheet. Uses the
/// list index because `RadioMacroStep` itself isn't `Identifiable`.
struct MacroStepEditTarget: Identifiable, Equatable {
    let index: Int

    var id: Int {
        index
    }
}

// MARK: - MacroEditorView+StepsSection

extension MacroEditorView {
    var stepsSection: some View {
        Section {
            if model.spec.steps.isEmpty {
                Text("No steps yet — tap Add Step to build your macro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.spec.steps.enumerated()), id: \.offset) { index, step in
                    MacroStepEditorRow(index: index, step: step)
                        .contentShape(Rectangle())
                        .onTapGesture { editStepTarget = MacroStepEditTarget(index: index) }
                        .contextMenu {
                            if index > 0 {
                                Button("Move Up") { moveStep(at: index, by: -1) }
                            }
                            if index < model.spec.steps.count - 1 {
                                Button("Move Down") { moveStep(at: index, by: 1) }
                            }
                            Button("Delete", role: .destructive) {
                                deleteSteps(IndexSet(integer: index))
                            }
                        }
                }
                .onDelete(perform: deleteSteps)
                .onMove(perform: moveSteps)
            }

            Button {
                addStepPicker = true
            } label: {
                Label("Add Step", systemImage: "plus.circle")
            }
        } header: {
            Text("Steps")
        } footer: {
            Text("Steps run top to bottom. Right-click for reorder + delete.")
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
            .frame(minWidth: 420, minHeight: 480)
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
            .frame(minWidth: 480, minHeight: 520)
        }
    }

    private func addStep(kind: RadioMacroStep.Kind) {
        let step = RadioMacroStep.defaultStep(for: kind)
        model.spec.steps.append(step)
        model.markDirty()
    }

    private func deleteSteps(_ indices: IndexSet) {
        model.spec.steps.remove(atOffsets: indices)
        model.markDirty()
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        model.spec.steps.move(fromOffsets: source, toOffset: destination)
        model.markDirty()
    }

    private func moveStep(at index: Int, by offset: Int) {
        let target = index + offset
        guard target >= 0, target < model.spec.steps.count else {
            return
        }
        let element = model.spec.steps.remove(at: index)
        model.spec.steps.insert(element, at: target)
        model.markDirty()
    }
}

// MARK: - MacroStepEditorRow

struct MacroStepEditorRow: View {
    let index: Int
    let step: RadioMacroStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            Image(systemName: step.iconName)
                .foregroundStyle(step.iconTint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.summaryTitle)
                    .font(.body)
                if let detail = step.summaryDetail {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - RadioMacroStep defaults + icon

extension RadioMacroStep {
    static func defaultStep(for kind: Kind) -> RadioMacroStep {
        switch kind {
        case .delay: .delay(durationMs: 500)
        case .setFrequency: .setFrequency(hz: 14_074_000)
        case .setMode: .setMode(mode: "USB")
        case .setPowerWatts: .setPowerWatts(watts: 5)
        case .setPTT: .setPTT(on: true)
        case .sendCW: .sendCW(text: "CQ CQ DE {ctx.MYCALL}")
        case .vendorCommand: .vendorCommand(commandId: "", args: nil)
        case .rawBytes: .rawBytes(protocol: "civ", bytes: "")
        case .readField: .readField(field: "vfoA", into: "currentFreq")
        case .waitUntil: .waitUntil(expr: "{ctx.MODE} == \"CW\"", timeoutMs: 5_000)
        case .assert: .assert(expr: "{ctx.MYCALL} != \"\"", message: "Missing callsign")
        }
    }

    var iconName: String {
        switch self {
        case .delay: "clock"
        case .setFrequency: "dial.high"
        case .setMode: "waveform.path"
        case .setPowerWatts: "bolt"
        case .setPTT: "antenna.radiowaves.left.and.right"
        case .sendCW: "ellipsis.message"
        case .vendorCommand: "command"
        case .rawBytes: "rectangle.dashed.badge.record"
        case .readField: "arrow.down.to.line"
        case .waitUntil: "hourglass"
        case .assert: "checkmark.shield"
        }
    }

    var iconTint: Color {
        switch self {
        case .setPTT,
             .sendCW: .red
        case .rawBytes: .orange
        case .setFrequency: .blue
        case .setMode: .teal
        case .setPowerWatts: .purple
        case .delay,
             .waitUntil: .secondary
        case .vendorCommand: .indigo
        case .readField: .green
        case .assert: .mint
        }
    }
}
