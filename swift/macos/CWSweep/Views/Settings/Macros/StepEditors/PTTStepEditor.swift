import CarrierWaveData
import SwiftUI

// MARK: - PTTStepEditor

/// Editor for `.setPTT(on:)`. Picker plus a reminder about the
/// executor's force-release behaviour so authors don't think they need
/// to add a defensive PTT-off step.
struct PTTStepEditor: View {
    @Binding var on: Bool

    var body: some View {
        Form {
            Section("PTT State") {
                Picker("State", selection: $on) {
                    Text("Press (ON)").tag(true)
                    Text("Release (OFF)").tag(false)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Label {
                    Text("The executor always drops PTT at the end of a " +
                        "macro and on any error — you don't need a " +
                        "defensive release step.")
                } icon: {
                    Image(systemName: "shield.checkered")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("PTT")
    }
}
