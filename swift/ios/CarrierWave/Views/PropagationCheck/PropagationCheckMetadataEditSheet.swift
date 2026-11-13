import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - PropagationCheckMetadataEditSheet

/// Edits the user-supplied metadata on a saved propagation check: notes plus
/// radio / antenna / key / mic. Uses the same `RadioPickerSheet` +
/// `EquipmentPickerSheet` the session metadata sheet uses so the user's saved
/// equipment lists are shared across surfaces.
struct PropagationCheckMetadataEditSheet: View {
    // MARK: Lifecycle

    init(check: PropagationCheck) {
        self.check = check
        _label = State(initialValue: check.label)
        _notes = State(initialValue: check.notes ?? "")
        _radio = State(initialValue: check.radio)
        _antenna = State(initialValue: check.antenna)
        _key = State(initialValue: check.key)
        _mic = State(initialValue: check.mic)
    }

    // MARK: Internal

    let check: PropagationCheck

    var body: some View {
        NavigationStack {
            Form {
                labelSection
                equipmentSection
                notesSection
            }
            .navigationTitle("Edit Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $activePicker) { picker in
                switch picker {
                case .radio:
                    RadioPickerSheet(selection: $radio)
                case .antenna:
                    EquipmentPickerSheet(equipmentType: .antenna, selection: $antenna)
                case .key:
                    EquipmentPickerSheet(equipmentType: .key, selection: $key)
                case .mic:
                    EquipmentPickerSheet(equipmentType: .mic, selection: $mic)
                }
            }
        }
    }

    // MARK: Private

    private enum PickerCategory: String, Identifiable {
        case radio
        case antenna
        case key
        case mic

        // MARK: Internal

        var id: String {
            rawValue
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var label: String
    @State private var notes: String
    @State private var radio: String?
    @State private var antenna: String?
    @State private var key: String?
    @State private var mic: String?
    @State private var activePicker: PickerCategory?

    private var labelSection: some View {
        Section {
            TextField("Untitled check", text: $label)
                .textInputAutocapitalization(.sentences)
        } header: {
            Text("Label")
        }
    }

    private var equipmentSection: some View {
        Section {
            equipmentRow(
                "Radio", icon: "radio", value: radio,
                action: { activePicker = .radio }
            )
            equipmentRow(
                "Antenna",
                icon: "antenna.radiowaves.left.and.right",
                value: antenna,
                action: { activePicker = .antenna }
            )
            equipmentRow(
                "Key", icon: "pianokeys", value: key,
                action: { activePicker = .key }
            )
            equipmentRow(
                "Mic", icon: "mic", value: mic,
                action: { activePicker = .mic }
            )
        } header: {
            Text("Equipment")
        }
    }

    private var notesSection: some View {
        Section {
            TextField(
                "What were you testing? Antenna height, conditions…",
                text: $notes,
                axis: .vertical
            )
            .lineLimit(3 ... 8)
        } header: {
            Text("Notes")
        }
    }

    private func equipmentRow(
        _ title: String, icon: String, value: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value ?? "None")
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func save() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        check.label = trimmedLabel
        check.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        check.radio = radio
        check.antenna = antenna
        check.key = key
        check.mic = mic
        try? modelContext.save()
        dismiss()
    }
}
