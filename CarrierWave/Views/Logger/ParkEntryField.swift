// Park Entry Field
//
// Enhanced field for entering one or more POTA park references.
// Shows selected parks as removable chips and supports adding
// via search picker or direct text entry. The binding stores
// parks as a comma-separated string for model compatibility.

import CarrierWaveCore
import SwiftUI

// MARK: - ParkEntryField

/// Multi-park entry field with chip display, search picker, and text entry
struct ParkEntryField: View {
    // MARK: Lifecycle

    init(
        parkReference: Binding<String>,
        label: String = "Park",
        placeholder: String = "K-1234",
        userGrid: String?,
        defaultCountry: String = "US"
    ) {
        _parkReference = parkReference
        self.label = label
        self.placeholder = placeholder
        self.userGrid = userGrid
        self.defaultCountry = defaultCountry
    }

    // MARK: Internal

    @Binding var parkReference: String

    let label: String
    let placeholder: String
    let userGrid: String?
    let defaultCountry: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label with count for multi-park
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selectedParks.count > 1 {
                    Text("(\(selectedParks.count)-fer)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            // Selected parks as removable chips
            if !selectedParks.isEmpty {
                parkChips
            }

            // Input row: TextField + search button
            addParkRow

            // Resolved park name for current text entry
            if let parkName = resolvedParkName {
                Text(parkName)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showPicker) {
            ParkPickerSheet(
                selectedParks: selectedParks,
                userGrid: userGrid,
                defaultCountry: defaultCountry,
                onAdd: { park in
                    addPark(park.reference)
                },
                onDismiss: { showPicker = false }
            )
        }
    }

    // MARK: Private

    @State private var showPicker = false
    @State private var resolvedParkName: String?
    @State private var textEntry = ""

    /// Parse the comma-separated binding into individual park references
    private var selectedParks: [String] {
        ParkReference.split(parkReference)
    }

    private var parkChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(selectedParks, id: \.self) { park in
                ParkChip(
                    reference: park,
                    name: POTAParksCache.shared.nameSync(for: park),
                    onRemove: { removePark(park) }
                )
            }
        }
    }

    private var addParkRow: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $textEntry)
                .font(.subheadline.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .onChange(of: textEntry) { _, newValue in
                    handleTextInput(newValue)
                }
                .onSubmit {
                    commitTextEntry()
                }

            Button {
                showPicker = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            if !textEntry.isEmpty {
                Button {
                    commitTextEntry()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func handleTextInput(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).uppercased()
        if let park = POTAParksCache.shared.lookupPark(
            trimmed, defaultCountry: defaultCountry
        ) {
            resolvedParkName = park.name
        } else {
            resolvedParkName = nil
        }
    }

    private func commitTextEntry() {
        let trimmed = textEntry.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return
        }

        // Try to resolve via cache (handles shorthand like "1234" -> "US-1234")
        if let park = POTAParksCache.shared.lookupPark(
            trimmed, defaultCountry: defaultCountry
        ) {
            addPark(park.reference)
        } else if ParkReference.isValid(trimmed) {
            addPark(trimmed)
        } else {
            // Try adding default country prefix
            let withPrefix = "\(defaultCountry)-\(trimmed)"
            if ParkReference.isValid(withPrefix) {
                addPark(withPrefix)
            }
        }

        textEntry = ""
        resolvedParkName = nil
    }

    private func addPark(_ reference: String) {
        let normalized = reference.uppercased()
        var parks = selectedParks
        guard !parks.contains(normalized) else {
            return
        }
        parks.append(normalized)
        parkReference = parks.joined(separator: ", ")
    }

    private func removePark(_ reference: String) {
        var parks = selectedParks
        parks.removeAll { $0 == reference }
        parkReference = parks.joined(separator: ", ")
    }
}

// MARK: - ParkChip

/// Removable chip showing a park reference and optional name
struct ParkChip: View {
    let reference: String
    var name: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(reference)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.green)

            if let name {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("Empty") {
    VStack {
        ParkEntryField(
            parkReference: .constant(""),
            userGrid: "FN31",
            defaultCountry: "US"
        )
    }
    .padding()
}

#Preview("Single Park") {
    VStack {
        ParkEntryField(
            parkReference: .constant("US-1234"),
            userGrid: "FN31",
            defaultCountry: "US"
        )
    }
    .padding()
}

#Preview("Multi-Park (Two-fer)") {
    VStack {
        ParkEntryField(
            parkReference: .constant("US-1044, US-3791"),
            userGrid: "FN31",
            defaultCountry: "US"
        )
    }
    .padding()
}
