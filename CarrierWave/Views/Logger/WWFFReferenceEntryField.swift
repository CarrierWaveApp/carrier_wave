// WWFF Reference Entry Field
//
// Field for entering a WWFF reference with chip display,
// live name resolution, and a search picker. Single-value binding.
// Mirrors SummitEntryField UX.

import SwiftUI

// MARK: - WWFFReferenceEntryField

/// WWFF reference entry field with chip display, live name lookup, and search picker
struct WWFFReferenceEntryField: View {
    // MARK: Internal

    @Binding var wwffReference: String

    /// User's grid square for nearby references fallback
    var userGrid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WWFF Reference")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !wwffReference.trimmingCharacters(in: .whitespaces).isEmpty {
                referenceChip
            }

            if wwffReference.trimmingCharacters(in: .whitespaces).isEmpty
                || isEditing
            {
                inputRow
            }

            if isEditing, let refName = resolvedRefName {
                Text(refName)
                    .font(.caption)
                    .foregroundStyle(.mint)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showPicker) {
            WWFFReferencePickerSheet(
                userGrid: userGrid,
                onSelect: { ref in
                    wwffReference = ref.reference
                    resolvedRefName = ref.name
                    textEntry = ""
                    isEditing = false
                    showPicker = false
                },
                onDismiss: { showPicker = false }
            )
        }
        .onAppear {
            resolveCurrentReference()
        }
    }

    // MARK: Private

    @State private var showPicker = false
    @State private var resolvedRefName: String?
    @State private var textEntry = ""
    @State private var isEditing = false

    private var referenceChip: some View {
        WWFFChip(
            code: wwffReference,
            name: resolvedRefName
                ?? WWFFReferencesCache.shared.nameSync(for: wwffReference),
            onRemove: {
                wwffReference = ""
                resolvedRefName = nil
                isEditing = false
            }
        )
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("KFF-1234", text: $textEntry)
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
            .accessibilityLabel("Search WWFF references")

            if !textEntry.isEmpty {
                Button {
                    commitTextEntry()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.mint)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set reference \(textEntry)")
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func handleTextInput(_ input: String) {
        let trimmed = input
            .trimmingCharacters(in: .whitespaces).uppercased()
        if let ref = WWFFReferencesCache.shared.lookupReference(trimmed) {
            resolvedRefName = ref.name
        } else {
            resolvedRefName = nil
        }
    }

    private func commitTextEntry() {
        let trimmed = textEntry
            .trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return
        }

        if let ref = WWFFReferencesCache.shared.lookupReference(trimmed) {
            wwffReference = ref.reference
            resolvedRefName = ref.name
        } else {
            wwffReference = trimmed
            resolvedRefName = nil
        }

        textEntry = ""
        isEditing = false
    }

    private func resolveCurrentReference() {
        let trimmed = wwffReference
            .trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return
        }
        if let ref = WWFFReferencesCache.shared.lookupReference(trimmed) {
            resolvedRefName = ref.name
        }
    }
}

// MARK: - WWFFChip

/// Removable chip showing a WWFF reference code and optional name
struct WWFFChip: View {
    let code: String
    var name: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(code)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.mint)

                if let name {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            .padding(.leading, 10)
            .padding(.vertical, 8)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(code)")
        }
        .background(Color.mint.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("Empty") {
    VStack {
        WWFFReferenceEntryField(
            wwffReference: .constant(""),
            userGrid: "FN31"
        )
    }
    .padding()
}

#Preview("With Reference") {
    VStack {
        WWFFReferenceEntryField(
            wwffReference: .constant("KFF-1234"),
            userGrid: "FN31"
        )
    }
    .padding()
}
