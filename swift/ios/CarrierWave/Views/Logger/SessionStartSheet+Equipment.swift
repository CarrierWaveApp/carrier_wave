import CarrierWaveData
import SwiftUI

// MARK: - SessionStartSheet Equipment Extension

extension SessionStartSheet {
    var sdrSection: some View {
        Section {
            sdrReceiverButton
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            if sdrAutoStart, !sdrLastReceiverHostPort.isEmpty {
                sdrAutoStartCard
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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

    /// Operators and attendees share one "People" section with the two
    /// inputs side by side. Operator chips keep a full-width row above so
    /// multi-op lists don't fight the attendees field for space.
    var peopleSection: some View {
        Section {
            if !additionalOperators.isEmpty {
                operatorChipsView
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Operators")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    operatorInputRow
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Attendees")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. KI7QCF", text: $attendeesText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.subheadline.monospaced())
                }
            }
            .padding(.vertical, 4)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } header: {
            Text("People")
        } footer: {
            Text(
                "Operators are logged as multi-op callsigns;"
                    + " attendees are just recorded. Both optional."
            )
        }
    }

    var operatorsSection: some View {
        Section {
            if !additionalOperators.isEmpty {
                operatorChipsView
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
            operatorInputRow
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } header: {
            Text("Additional Operators")
        } footer: {
            Text("Add callsigns for multi-op sessions (optional)")
        }
    }

    private var operatorChipsView: some View {
        FlowLayout(spacing: 6) {
            ForEach(additionalOperators, id: \.self) { callsign in
                operatorChip(callsign)
            }
        }
        .padding(.vertical, 4)
    }

    private func operatorChip(_ callsign: String) -> some View {
        HStack(spacing: 4) {
            Text(callsign)
                .font(.subheadline.monospaced().weight(.medium))
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    additionalOperators.removeAll { $0 == callsign }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemFill))
        .clipShape(Capsule())
    }

    private var operatorInputRow: some View {
        HStack {
            TextField(
                additionalOperators.isEmpty ? "e.g. W1AW" : "Add another",
                text: $operatorInput
            )
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.subheadline.monospaced())
            .onSubmit {
                commitOperatorInput()
            }
            .onChange(of: operatorInput) { _, newValue in
                // Auto-commit on comma or space
                if newValue.hasSuffix(",") || newValue.hasSuffix(" ") {
                    commitOperatorInput()
                }
            }

            if !operatorInput.isEmpty {
                Button("Add") {
                    commitOperatorInput()
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    private func commitOperatorInput() {
        let myCall = fullCallsign.uppercased()
        let candidates = operatorInput
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty && $0 != myCall }

        for call in candidates where !additionalOperators.contains(call) {
            withAnimation(.easeInOut(duration: 0.2)) {
                additionalOperators.append(call)
            }
        }
        operatorInput = ""
    }

    var notesSection: some View {
        Section {
            TextField("Session notes", text: $sessionNotes, axis: .vertical)
                .lineLimit(4)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            saveDefaultsRow
        } header: {
            Text("Notes")
        } footer: {
            Text("Defaults pre-fill new sessions. Equipment lives in loadouts at the top.")
        }
    }
}
