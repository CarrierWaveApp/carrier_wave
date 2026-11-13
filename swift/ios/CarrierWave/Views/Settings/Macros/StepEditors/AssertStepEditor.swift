import CarrierWaveData
import SwiftUI

// MARK: - AssertStepEditor

/// Editor for `.assert(expr:message:)`. Asserts halt the macro with the
/// user-supplied message; useful for pre-flight checks that don't fit
/// the safety gate (e.g. "abort if frequency not in expected band").
struct AssertStepEditor: View {
    @Binding var expr: String
    @Binding var message: String

    var body: some View {
        Form {
            Section("Condition") {
                TextField("{ctx.MODE} == \"CW\"", text: $expr, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.body.monospaced())
                Text("Macro halts if this evaluates false.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Failure message") {
                TextField("Mode must be CW", text: $message, axis: .vertical)
                    .lineLimit(2 ... 4)
                Text("Shown in the run log if the assertion fails.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Assert")
    }
}
