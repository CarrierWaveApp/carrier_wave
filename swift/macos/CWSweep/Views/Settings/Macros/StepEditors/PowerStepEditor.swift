import CarrierWaveData
import SwiftUI

// MARK: - PowerStepEditor

/// Editor for `.setPowerWatts(watts:)`. Slider + numeric input that
/// caps at 100 W to discourage authoring high-power macros — users who
/// want more can edit the saved spec directly.
struct PowerStepEditor: View {
    @Binding var watts: UInt64

    var body: some View {
        Form {
            Section("Power") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(watts) },
                            set: { watts = UInt64($0) }
                        ),
                        in: 0 ... 100,
                        step: 1
                    )
                    Text("\(watts) W")
                        .font(.body.monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                }
                TextField("Watts", value: $watts, formatter: NumberFormatter())
                Text("QRP = 5 W, low power = 25 W, full output = your rig's max.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Set Power")
    }
}
