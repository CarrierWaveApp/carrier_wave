// Park Entry Field
//
// Enhanced field for entering one or more POTA park references.
// Shows selected parks as removable chips and supports adding
// via search picker or direct text entry. The binding stores
// parks as a comma-separated string for model compatibility.

import CarrierWaveData
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
        defaultCountry: String = "US",
        onParkGridChanged: ((String?) -> Void)? = nil
    ) {
        _parkReference = parkReference
        self.label = label
        self.placeholder = placeholder
        self.userGrid = userGrid
        self.defaultCountry = defaultCountry
        self.onParkGridChanged = onParkGridChanged
    }

    // MARK: Internal

    @Binding var parkReference: String

    let label: String
    let placeholder: String
    let userGrid: String?
    let defaultCountry: String
    let onParkGridChanged: ((String?) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Label with count for multi-park
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if selectedParks.count > 1 {
                    Text("(\(selectedParks.count)-fer)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            if selectedParks.isEmpty {
                // No park chosen yet: full search box + nearby suggestions
                addParkRow

                // Resolved park name for current text entry
                if let parkName = resolvedParkName {
                    Text(parkName)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }

                NearbyParkSuggestions(
                    userGrid: userGrid,
                    defaultCountry: defaultCountry,
                    selectedParks: selectedParks,
                    onAdd: { park in
                        addPark(park.reference)
                        onParkGridChanged?(park.grid)
                    }
                )
                .loadOnAppear()
            } else {
                // Park chosen: enriched cards instead of the search box
                ForEach(selectedParks, id: \.self) { park in
                    SelectedParkCard(
                        reference: park,
                        onRemove: { removePark(park) }
                    )
                }

                addAnotherButton
            }
        }
        .sheet(isPresented: $showPicker) {
            ParkPickerSheet(
                selectedParks: selectedParks,
                userGrid: userGrid,
                defaultCountry: defaultCountry,
                onAdd: { park in
                    addPark(park.reference)
                    onParkGridChanged?(park.grid)
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

    /// Low-key affordance to add a second park (n-fer / rove) without
    /// bringing back the always-on search box once a park is chosen.
    private var addAnotherButton: some View {
        Button {
            showPicker = true
        } label: {
            Label("Add another park", systemImage: "plus.circle")
                .font(.subheadline)
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
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
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search parks")

            if !textEntry.isEmpty {
                Button {
                    commitTextEntry()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add park \(textEntry)")
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            onParkGridChanged?(park.grid)
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
