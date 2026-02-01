// Park Entry Field
//
// Enhanced text field for entering POTA park references with
// integrated search picker and number shorthand expansion.

import SwiftUI

// MARK: - ParkEntryField

/// Enhanced park entry field with search picker and number shorthand
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
            // Label
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Input row: TextField + magnifying glass button
            HStack(spacing: 8) {
                TextField(placeholder, text: $parkReference)
                    .font(.subheadline.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: parkReference) { _, newValue in
                        handleParkInput(newValue)
                    }

                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Park name display (if valid reference)
            if let parkName = resolvedParkName {
                Text(parkName)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showPicker) {
            ParkPickerSheet(
                selectedPark: $parkReference,
                userGrid: userGrid,
                defaultCountry: defaultCountry,
                onDismiss: { showPicker = false }
            )
        }
    }

    // MARK: Private

    @State private var showPicker = false
    @State private var resolvedParkName: String?

    private func handleParkInput(_ input: String) {
        // Use POTAParksCache.shared.lookupPark() with defaultCountry
        // This handles shorthand: "1234" -> "US-1234"
        let trimmed = input.trimmingCharacters(in: .whitespaces).uppercased()
        if let park = POTAParksCache.shared.lookupPark(trimmed, defaultCountry: defaultCountry) {
            resolvedParkName = park.name
        } else {
            resolvedParkName = nil
        }
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

#Preview("With Reference") {
    VStack {
        ParkEntryField(
            parkReference: .constant("US-1234"),
            userGrid: "FN31",
            defaultCountry: "US"
        )
    }
    .padding()
}
