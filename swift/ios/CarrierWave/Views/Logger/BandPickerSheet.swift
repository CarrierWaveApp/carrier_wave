import CarrierWaveCore
import SwiftUI

// MARK: - BandPickerSheet

/// Searchable ADIF band picker showing each band with its primary frequency range.
/// Bands are ordered low-to-high as in the ADIF spec; a custom-entry row covers
/// non-standard or experimental bands.
struct BandPickerSheet: View {
    // MARK: Lifecycle

    init(
        currentCode: String,
        onSelect: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.currentCode = currentCode.lowercased()
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    // MARK: Internal

    let currentCode: String
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                customEntrySection

                Section {
                    let bands = filteredBands
                    if bands.isEmpty {
                        ContentUnavailableView.search(text: trimmedSearch)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(bands, id: \.code) { band in
                            bandRow(band)
                        }
                    }
                } header: {
                    Text("ADIF Bands")
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Band or frequency")
            .autocorrectionDisabled()
            .navigationTitle("Band")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }

    // MARK: Private

    @State private var searchText = ""
    @State private var customText = ""

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var filteredBands: [ADIFCatalog.Band] {
        let query = trimmedSearch.lowercased()
        guard !query.isEmpty else {
            return ADIFCatalog.bands
        }
        return ADIFCatalog.bands.filter { band in
            band.code.lowercased().contains(query)
                || band.description.lowercased().contains(query)
        }
    }

    private var customEntrySection: some View {
        Section {
            HStack {
                TextField("Custom band code (e.g. 1.5m)", text: $customText)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()

                Button("Use") {
                    commitCustomEntry()
                }
                .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Custom")
        } footer: {
            Text("Use for experimental bands or allocations outside the ADIF catalog.")
        }
    }

    private func bandRow(_ band: ADIFCatalog.Band) -> some View {
        Button {
            onSelect(band.code)
        } label: {
            HStack(spacing: 12) {
                Text(band.code)
                    .font(.body.monospaced().weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 70, alignment: .leading)

                Text(band.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if band.code.lowercased() == currentCode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commitCustomEntry() {
        let trimmed = customText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else {
            return
        }
        onSelect(trimmed)
    }
}

#Preview {
    BandPickerSheet(
        currentCode: "20m",
        onSelect: { print("Selected: \($0)") },
        onDismiss: {}
    )
}
