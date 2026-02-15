import SwiftUI

// MARK: - SessionEquipmentEditSheet

/// Compact sheet for editing all equipment fields during an active session.
struct SessionEquipmentEditSheet: View {
    // MARK: Internal

    @Binding var radio: String?
    @Binding var antenna: String?
    @Binding var key: String?
    @Binding var mic: String?
    @Binding var extraEquipment: String?

    /// Current session mode, used to conditionally show key/mic rows
    let mode: String

    var body: some View {
        NavigationStack {
            List {
                equipmentRow("Radio", icon: "radio", value: radio) {
                    showRadioPicker = true
                }
                equipmentRow(
                    "Antenna", icon: "antenna.radiowaves.left.and.right",
                    value: antenna
                ) {
                    showAntennaPicker = true
                }
                if mode == "CW" {
                    equipmentRow("Key", icon: "pianokeys", value: key) {
                        showKeyPicker = true
                    }
                }
                if ["SSB", "USB", "LSB", "AM", "FM"].contains(mode) {
                    equipmentRow("Mic", icon: "mic", value: mic) {
                        showMicPicker = true
                    }
                }
                Section {
                    TextField("Other equipment", text: extraEquipmentText)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle("Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showRadioPicker) {
                RadioPickerSheet(selection: $radio)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showAntennaPicker) {
                EquipmentPickerSheet(equipmentType: .antenna, selection: $antenna)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showKeyPicker) {
                EquipmentPickerSheet(equipmentType: .key, selection: $key)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showMicPicker) {
                EquipmentPickerSheet(equipmentType: .mic, selection: $mic)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var showRadioPicker = false
    @State private var showAntennaPicker = false
    @State private var showKeyPicker = false
    @State private var showMicPicker = false

    /// Binding adapter for optional extraEquipment string
    private var extraEquipmentText: Binding<String> {
        Binding(
            get: { extraEquipment ?? "" },
            set: { extraEquipment = $0.isEmpty ? nil : $0 }
        )
    }

    private func equipmentRow(
        _ label: String, icon: String, value: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value ?? "None")
                    .foregroundStyle(value != nil ? .primary : .secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
