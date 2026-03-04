// Summit Entry Field
//
// Field for entering a SOTA summit reference with chip display,
// live name resolution, and a search picker. Single-value binding.
// Mirrors ParkEntryField UX (minus multi-select).

import CarrierWaveData
import SwiftUI

// MARK: - SummitEntryField

/// Summit entry field with chip display, live name lookup, and search picker
struct SummitEntryField: View {
    // MARK: Internal

    @Binding var sotaReference: String

    /// User's grid square for nearby summits fallback
    var userGrid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Label
            Text("Summit")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Selected summit as removable chip
            if !sotaReference.trimmingCharacters(in: .whitespaces).isEmpty {
                summitChip
            }

            // Input row: TextField + search button (shown when no summit or editing)
            if sotaReference.trimmingCharacters(in: .whitespaces).isEmpty || isEditing {
                inputRow
            }

            // Resolved summit name for current text entry
            if isEditing, let summitName = resolvedSummitName {
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
    @State private var resolvedSummitName: String?
    @State private var textEntry = ""
    @State private var isEditing = false

    private var summitChip: some View {
        SummitChip(
            code: sotaReference,
            name: resolvedSummitName
                ?? SOTASummitsCache.shared.nameSync(for: sotaReference),
            onRemove: {
                sotaReference = ""
                resolvedSummitName = nil
                isEditing = false
            }
        )
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("W4C/CM-001", text: $textEntry)
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
            .accessibilityLabel("Search summits")

            if !textEntry.isEmpty {
                Button {
                    commitTextEntry()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set summit \(textEntry)")
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func handleTextInput(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).uppercased()
        if let summit = SOTASummitsCache.shared.lookupSummit(trimmed) {
            resolvedSummitName = summit.name
        } else {
            resolvedSummitName = nil
        }
    }

    private func commitTextEntry() {
        let trimmed = textEntry.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return
        }

        // Try to resolve via cache
        if let summit = SOTASummitsCache.shared.lookupSummit(trimmed) {
            sotaReference = summit.code
            resolvedSummitName = summit.name
        } else {
            // Accept raw text entry (user might know a code not in cache)
            sotaReference = trimmed
            resolvedSummitName = nil
        }

        textEntry = ""
        isEditing = false
    }

    private func resolveCurrentReference() {
        let trimmed = sotaReference.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return
        }
        if let summit = SOTASummitsCache.shared.lookupSummit(trimmed) {
            resolvedSummitName = summit.name
        }
    }
}

// MARK: - SummitChip

/// Removable chip showing a summit code and optional name
struct SummitChip: View {
    let code: String
    var name: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(code)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.green)

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
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
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
