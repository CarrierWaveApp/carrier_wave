import SwiftUI

// MARK: - SessionStartSheet Equipment Extension

extension SessionStartSheet {
    var powerSection: some View {
        Section {
            HStack {
                TextField("100", text: $powerText)
                    .keyboardType(.numberPad)
                    .font(.title3.monospaced())

                Text("W")
                    .foregroundStyle(.secondary)
            }

            if let warning = powerWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Power")
        } footer: {
            Text("Transmit power in watts (optional). US max is 1,500W.")
        }
    }

    var equipmentSection: some View {
        Section {
            // Radio picker (moved from +Sections)
            Button {
                showRadioPicker = true
            } label: {
                HStack {
                    Label(
                        selectedRadio ?? "None",
                        systemImage: "radio"
                    )
                    .foregroundStyle(selectedRadio != nil ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            DisclosureGroup("More Equipment", isExpanded: $showMoreEquipment) {
                // Antenna picker
                Button {
                    showAntennaPicker = true
                } label: {
                    HStack {
                        Label(
                            selectedAntenna ?? "None",
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                        .foregroundStyle(selectedAntenna != nil ? .primary : .secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Key picker (CW only)
                if selectedMode == "CW" {
                    Button {
                        showKeyPicker = true
                    } label: {
                        HStack {
                            Label(
                                selectedKey ?? "None",
                                systemImage: "pianokeys"
                            )
                            .foregroundStyle(selectedKey != nil ? .primary : .secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Mic picker (voice modes)
                if ["SSB", "USB", "LSB", "AM", "FM"].contains(selectedMode) {
                    Button {
                        showMicPicker = true
                    } label: {
                        HStack {
                            Label(
                                selectedMic ?? "None",
                                systemImage: "mic"
                            )
                            .foregroundStyle(selectedMic != nil ? .primary : .secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Extra equipment text
                TextField("Other equipment", text: $extraEquipmentText)
                    .textInputAutocapitalization(.sentences)
            }
        } header: {
            Text("Equipment")
        } footer: {
            Text("Radio and other equipment for this session (optional)")
        }
    }

    var attendeesSection: some View {
        Section {
            TextField("e.g. KI7QCF, N0CALL", text: $attendeesText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text("Attendees")
        } footer: {
            Text("Comma-separated callsigns of other operators (optional)")
        }
    }

    var notesSection: some View {
        Section {
            TextField("Session notes", text: $sessionNotes, axis: .vertical)
                .lineLimit(3 ... 6)
        } header: {
            Text("Notes")
        } footer: {
            Text("Any notes about this session (optional)")
        }
    }
}
