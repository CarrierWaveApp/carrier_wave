import CarrierWaveData
import SwiftUI

// MARK: - ModeStepEditor

/// Editor for `.setMode(mode:)`. Offers a picker of common modes plus a
/// free-text field for unusual / vendor-specific modes.
struct ModeStepEditor: View {
    // MARK: Internal

    @Binding var mode: String

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Quick pick", selection: pickerBinding) {
                    Text("Custom…").tag("")
                    ForEach(Self.commonModes, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.menu)

                TextField("Mode string", text: $mode)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)

                Text("Stored uppercased at run time. " +
                    "Common: USB, LSB, CW, CWR, FM, AM, RTTY, FT8, FT4, PSK31.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Set Mode")
    }

    // MARK: Private

    private static let commonModes: [String] = [
        "USB", "LSB", "CW", "CWR", "FM", "AM", "RTTY", "FT8", "FT4", "PSK31",
        "DATA-U", "DATA-L",
    ]

    private var pickerBinding: Binding<String> {
        Binding(
            get: {
                Self.commonModes.contains(mode.uppercased()) ? mode.uppercased() : ""
            },
            set: { newValue in
                guard !newValue.isEmpty else {
                    return
                }
                mode = newValue
            }
        )
    }
}
