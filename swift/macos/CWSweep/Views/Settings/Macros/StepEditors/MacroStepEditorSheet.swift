import CarrierWaveData
import SwiftUI

// MARK: - MacroStepEditorSheet

/// Dispatch sheet that routes to the per-kind step editor. Each kind
/// owns a small dedicated editor under `StepEditors/`. The wrapper
/// handles Save / Cancel and storing the result back via `onSave`.
struct MacroStepEditorSheet: View {
    // MARK: Lifecycle

    init(step: RadioMacroStep, onSave: @escaping (RadioMacroStep) -> Void) {
        self.step = step
        self.onSave = onSave
        _draft = State(wrappedValue: step)
    }

    // MARK: Internal

    let step: RadioMacroStep
    let onSave: (RadioMacroStep) -> Void

    var body: some View {
        editor
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var draft: RadioMacroStep

    @ViewBuilder
    private var editor: some View {
        switch draft {
        case let .delay(durationMs):
            DelayStepEditor(durationMs: Binding(
                get: { durationMs },
                set: { draft = .delay(durationMs: $0) }
            ))
        case let .setFrequency(hz):
            FrequencyStepEditor(hz: Binding(
                get: { hz },
                set: { draft = .setFrequency(hz: $0) }
            ))
        case let .setMode(mode):
            ModeStepEditor(mode: Binding(
                get: { mode },
                set: { draft = .setMode(mode: $0) }
            ))
        case let .setPowerWatts(watts):
            PowerStepEditor(watts: Binding(
                get: { watts },
                set: { draft = .setPowerWatts(watts: $0) }
            ))
        case let .setPTT(on):
            PTTStepEditor(on: Binding(
                get: { on },
                set: { draft = .setPTT(on: $0) }
            ))
        case let .sendCW(text):
            CWStepEditor(text: Binding(
                get: { text },
                set: { draft = .sendCW(text: $0) }
            ))
        case let .vendorCommand(commandId, args):
            VendorCommandPickerView(
                commandId: Binding(
                    get: { commandId },
                    set: { draft = .vendorCommand(commandId: $0, args: args) }
                ),
                args: Binding(
                    get: { args },
                    set: { draft = .vendorCommand(commandId: commandId, args: $0) }
                )
            )
        case let .rawBytes(protocolName, bytes):
            RawBytesStepEditor(
                protocolName: Binding(
                    get: { protocolName },
                    set: { draft = .rawBytes(protocol: $0, bytes: bytes) }
                ),
                bytes: Binding(
                    get: { bytes },
                    set: { draft = .rawBytes(protocol: protocolName, bytes: $0) }
                )
            )
        case let .readField(field, into):
            ReadFieldStepEditor(
                field: Binding(
                    get: { field },
                    set: { draft = .readField(field: $0, into: into) }
                ),
                into: Binding(
                    get: { into },
                    set: { draft = .readField(field: field, into: $0) }
                )
            )
        case let .waitUntil(expr, timeoutMs):
            WaitUntilStepEditor(
                expr: Binding(
                    get: { expr },
                    set: { draft = .waitUntil(expr: $0, timeoutMs: timeoutMs) }
                ),
                timeoutMs: Binding(
                    get: { timeoutMs },
                    set: { draft = .waitUntil(expr: expr, timeoutMs: $0) }
                )
            )
        case let .assert(expr, message):
            AssertStepEditor(
                expr: Binding(
                    get: { expr },
                    set: { draft = .assert(expr: $0, message: message) }
                ),
                message: Binding(
                    get: { message },
                    set: { draft = .assert(expr: expr, message: $0) }
                )
            )
        }
    }
}
