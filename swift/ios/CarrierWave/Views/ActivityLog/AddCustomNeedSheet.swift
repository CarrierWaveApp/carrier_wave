// Add Custom Need Sheet
//
// Sheet for creating user-defined needs (Phase 3).
// Supports callsign patterns, entity codes, US states, and park references.

import SwiftData
import SwiftUI

// MARK: - AddCustomNeedSheet

struct AddCustomNeedSheet: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $patternType) {
                        Text("Callsign").tag("callsign")
                        Text("US State").tag("state")
                        Text("Park Reference").tag("parkRef")
                    }

                    TextField(placeholderText, text: $pattern)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    TextField("Description", text: $label)
                } header: {
                    Text("Pattern")
                } footer: {
                    Text(footerText)
                }

                Section {
                    previewSection
                }
            }
            .navigationTitle("Add Custom Need")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveNeed()
                        dismiss()
                    }
                    .disabled(pattern.isEmpty || label.isEmpty)
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var patternType = "callsign"
    @State private var pattern = ""
    @State private var label = ""

    private var placeholderText: String {
        switch patternType {
        case "callsign": "VK9*"
        case "state": "WY"
        case "parkRef": "K-1234"
        default: "Pattern"
        }
    }

    private var footerText: String {
        switch patternType {
        case "callsign":
            "Use * as wildcard. Example: VK9* matches all VK9 callsigns."
        case "state":
            "2-letter US state code."
        case "parkRef":
            "POTA or WWFF reference. Example: K-1234 or KFF-1234."
        default:
            ""
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if !pattern.isEmpty, !label.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading) {
                    Text(pattern)
                        .font(.subheadline.monospaced())
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Fill in pattern and description to preview")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func saveNeed() {
        let need = CustomNeed(
            pattern: pattern.trimmingCharacters(in: .whitespaces),
            patternTypeRaw: patternType,
            label: label.trimmingCharacters(in: .whitespaces)
        )
        modelContext.insert(need)
    }
}
