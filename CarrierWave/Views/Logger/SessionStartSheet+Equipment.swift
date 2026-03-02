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

    var sdrSection: some View {
        Section {
            sdrReceiverButton
            if sdrAutoStart, !sdrLastReceiverHostPort.isEmpty {
                sdrAutoStartCard
            }
        } header: {
            Text("WebSDR")
        } footer: {
            if frequency.isEmpty {
                Text("Enter a frequency above to select a WebSDR receiver")
            }
        }
    }

    @ViewBuilder
    private var sdrReceiverButton: some View {
        if frequency.isEmpty {
            // Disabled state — no frequency entered
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose Receiver")
                            .font(.subheadline.weight(.medium))
                        Text("Requires a frequency")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .foregroundStyle(.secondary)
        } else {
            Button {
                showSDRPicker = true
            } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            if sdrAutoStart, !sdrLastReceiverHostPort.isEmpty {
                                Text(sdrReceiverDisplayName)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text("Auto-start enabled")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("Choose Receiver")
                                    .font(.subheadline.weight(.medium))
                                Text("None selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(
                                sdrAutoStart ? .blue : .secondary
                            )
                    }
                    Spacer()
                    if sdrAutoStart {
                        Button {
                            sdrAutoStart = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove SDR receiver")
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var sdrReceiverDisplayName: String {
        sdrLastReceiverName.isEmpty ? sdrLastReceiverHostPort : sdrLastReceiverName
    }

    private var sdrAutoStartCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("SDR will auto-connect")
                    .font(.subheadline.weight(.semibold))
                Text("Recording starts from \(sdrReceiverDisplayName) when the session begins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.blue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
