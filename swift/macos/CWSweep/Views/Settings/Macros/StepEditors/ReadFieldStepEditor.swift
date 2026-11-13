import CarrierWaveData
import SwiftUI

// MARK: - ReadFieldStepEditor

/// Editor for `.readField(field:into:)`. Field names are loosely typed
/// strings the sink interprets (the macOS sink supports `vfoA` + `mode`
/// today). The `into` name binds the result into `ctx.<name>` for
/// downstream steps.
struct ReadFieldStepEditor: View {
    @Binding var field: String
    @Binding var into: String

    var body: some View {
        Form {
            Section("Read") {
                Picker("Field", selection: $field) {
                    Text("VFO A frequency").tag("vfoA")
                    Text("Current mode").tag("mode")
                    Text("Custom…").tag("custom")
                }
                .pickerStyle(.menu)
                if field == "custom" || !["vfoA", "mode"].contains(field) {
                    TextField("Field name", text: $field)
                }
                Text("Sweep sink today exposes `vfoA` (Hz) and `mode`. " +
                    "Other fields return empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Store as") {
                TextField("ctx variable name", text: $into)
                if !into.isEmpty {
                    Text("Use `{ctx.\(into)}` in later steps to read this value.")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Read Field")
    }
}
