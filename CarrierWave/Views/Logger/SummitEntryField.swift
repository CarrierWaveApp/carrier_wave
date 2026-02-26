// Summit Entry Field
//
// Field for entering a SOTA summit reference with live name
// resolution and a search picker. Single-value binding (not
// comma-separated like ParkEntryField).

import SwiftUI

// MARK: - SummitEntryField

/// Summit entry field with live name lookup and search picker
struct SummitEntryField: View {
    // MARK: Internal

    @Binding var sotaReference: String

    /// User's grid square for nearby summits fallback
    var userGrid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Summit")
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("W4C/CM-001", text: $sotaReference)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospaced())
                    .onChange(of: sotaReference) { _, newValue in
                        handleTextInput(newValue)
                    }

                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search summits")
            }

            if let summitName = resolvedSummitName {
                Text(summitName)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showPicker) {
            SummitPickerSheet(
                userGrid: userGrid,
                onSelect: { summit in
                    sotaReference = summit.code
                    resolvedSummitName = summit.name
                    showPicker = false
                },
                onDismiss: { showPicker = false }
            )
        }
        .onAppear {
            handleTextInput(sotaReference)
        }
    }

    // MARK: Private

    @State private var showPicker = false
    @State private var resolvedSummitName: String?

    private func handleTextInput(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).uppercased()
        if let summit = SOTASummitsCache.shared.lookupSummit(trimmed) {
            resolvedSummitName = summit.name
        } else {
            resolvedSummitName = nil
        }
    }
}

// MARK: - Preview

#Preview("Empty") {
    VStack {
        SummitEntryField(
            sotaReference: .constant(""),
            userGrid: "FN31"
        )
    }
    .padding()
}

#Preview("With Reference") {
    VStack {
        SummitEntryField(
            sotaReference: .constant("W4C/CM-001"),
            userGrid: "FN31"
        )
    }
    .padding()
}
