// Single Reference Entry Field
//
// Generic field for entering a single reference (summit, WWFF, etc.)
// with chip display, live name resolution, and a search picker.
// Replaces the near-identical SummitEntryField and
// WWFFReferenceEntryField with a configurable implementation.

import SwiftUI

// MARK: - ReferenceEntryConfig

/// Configuration for a SingleReferenceEntryField
struct ReferenceEntryConfig {
    let label: String
    let placeholder: String
    let accentColor: Color
    let searchLabel: String

    /// Look up a reference code and return (canonicalCode, name), or nil
    let lookupReference: (String) -> (code: String, name: String)?

    /// Synchronous name lookup for chip display
    let nameSync: (String) -> String?
}

// MARK: - SingleReferenceEntryField

/// Single-value reference entry field with chip, live name lookup, and search picker
struct SingleReferenceEntryField<PickerContent: View>: View {
    // MARK: Internal

    @Binding var reference: String

    let config: ReferenceEntryConfig
    var userGrid: String?

    /// Builder for the picker sheet content
    @ViewBuilder let pickerSheet: (
        _ onSelect: @escaping (_ code: String, _ name: String) -> Void,
        _ onDismiss: @escaping () -> Void
    ) -> PickerContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(config.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !reference.trimmingCharacters(in: .whitespaces).isEmpty {
                ReferenceChip(
                    code: reference,
                    name: resolvedName ?? config.nameSync(reference),
                    accentColor: config.accentColor,
                    onRemove: {
                        reference = ""
                        resolvedName = nil
                        isEditing = false
                    }
                )
            }

            if reference.trimmingCharacters(in: .whitespaces).isEmpty || isEditing {
                inputRow
            }

            if isEditing, let name = resolvedName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(config.accentColor)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showPicker) {
            pickerSheet(
                { code, name in
                    reference = code
                    resolvedName = name
                    textEntry = ""
                    isEditing = false
                    showPicker = false
                },
                { showPicker = false }
            )
        }
        .onAppear {
            resolveCurrentReference()
        }
    }

    // MARK: Private

    @State private var showPicker = false
    @State private var resolvedName: String?
    @State private var textEntry = ""
    @State private var isEditing = false

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField(config.placeholder, text: $textEntry)
                .font(.subheadline.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: textEntry) { _, newValue in
                    isEditing = true
                    handleTextInput(newValue)
                }
                .onSubmit {
                    commitTextEntry()
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
            .accessibilityLabel(config.searchLabel)

            if !textEntry.isEmpty {
                Button {
                    commitTextEntry()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(config.accentColor)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set \(config.label.lowercased()) \(textEntry)")
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func handleTextInput(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).uppercased()
        if let result = config.lookupReference(trimmed) {
            resolvedName = result.name
        } else {
            resolvedName = nil
        }
    }

    private func commitTextEntry() {
        let trimmed = textEntry.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return
        }

        if let result = config.lookupReference(trimmed) {
            reference = result.code
            resolvedName = result.name
        } else {
            reference = trimmed
            resolvedName = nil
        }

        textEntry = ""
        isEditing = false
    }

    private func resolveCurrentReference() {
        let trimmed = reference.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return
        }
        if let result = config.lookupReference(trimmed) {
            resolvedName = result.name
        }
    }
}
