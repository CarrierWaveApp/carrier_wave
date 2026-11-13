import CarrierWaveData
import SwiftUI

// MARK: - PropagationCheckMetadataCard

/// Read-only display of the user-supplied notes + equipment on a propagation
/// check. Hidden when nothing is set. Edit via `PropagationCheckMetadataEditSheet`.
struct PropagationCheckMetadataCard: View {
    // MARK: Internal

    let check: PropagationCheck

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 12) {
                if !equipmentEntries.isEmpty {
                    equipmentBlock
                }
                if let notes = trimmedNotes {
                    if !equipmentEntries.isEmpty {
                        Divider()
                    }
                    notesBlock(notes)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Private

    private var hasContent: Bool {
        !equipmentEntries.isEmpty || trimmedNotes != nil
    }

    private var trimmedNotes: String? {
        guard let raw = check.notes else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var equipmentEntries: [EquipmentEntry] {
        [
            EquipmentEntry(icon: "radio", label: "Radio", value: check.radio),
            EquipmentEntry(
                icon: "antenna.radiowaves.left.and.right",
                label: "Antenna",
                value: check.antenna
            ),
            EquipmentEntry(icon: "pianokeys", label: "Key", value: check.key),
            EquipmentEntry(icon: "mic", label: "Mic", value: check.mic),
        ].compactMap { entry in
            guard let value = entry.value?.trimmingCharacters(in: .whitespaces),
                  !value.isEmpty
            else {
                return nil
            }
            return EquipmentEntry(icon: entry.icon, label: entry.label, value: value)
        }
    }

    private var equipmentBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Equipment")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(equipmentEntries) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.icon)
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(entry.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.value ?? "")
                        .font(.body.monospaced())
                }
                .font(.subheadline)
            }
        }
    }

    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(notes)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - EquipmentEntry

private struct EquipmentEntry: Identifiable {
    let icon: String
    let label: String
    let value: String?

    var id: String {
        label
    }
}
