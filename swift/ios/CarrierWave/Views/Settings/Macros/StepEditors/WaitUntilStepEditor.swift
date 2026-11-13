import CarrierWaveData
import SwiftUI

// MARK: - WaitUntilStepEditor

/// Editor for `.waitUntil(expr:timeoutMs:)`. The expression is a
/// `MacroTemplateEngine` boolean — comparisons against `{ctx.*}` and
/// `{arg.*}` values. Verifier caps `timeoutMs` at 30,000.
struct WaitUntilStepEditor: View {
    @Binding var expr: String
    @Binding var timeoutMs: UInt64

    var body: some View {
        Form {
            Section("Condition") {
                TextField("{ctx.MODE} == \"CW\"", text: $expr, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.body.monospaced())
                Text("Comparisons: ==, !=, <, <=, >, >=. References must " +
                    "use `{ctx.*}` or `{arg.*}` namespaces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Timeout") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(timeoutMs) },
                            set: { timeoutMs = UInt64($0) }
                        ),
                        in: 100 ... 30_000,
                        step: 100
                    )
                    Text("\(timeoutMs) ms")
                        .font(.body.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
                if timeoutMs >= 30_000 {
                    Text("At verifier cap (30,000 ms).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Wait Until")
    }
}
