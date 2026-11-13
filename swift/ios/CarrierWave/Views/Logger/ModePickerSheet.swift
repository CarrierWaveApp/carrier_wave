import CarrierWaveCore
import SwiftUI

// MARK: - ModePickerSheet

/// Searchable ADIF mode picker grouped by category (Phone/CW/Digital/Image).
/// Includes a custom-entry row for obscure or proprietary modes not in
/// `ADIFCatalog.modes`.
struct ModePickerSheet: View {
    // MARK: Lifecycle

    init(
        currentCode: String,
        onSelect: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.currentCode = currentCode.uppercased()
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

                ForEach(ADIFCatalog.ModeCategory.allCases, id: \.self) { category in
                    let modes = filteredModes(in: category)
                    if !modes.isEmpty {
                        Section(category.rawValue) {
                            ForEach(modes, id: \.code) { mode in
                                modeRow(mode)
                            }
                        }
                    }
                }

                if allFilteredEmpty, !trimmedSearch.isEmpty {
                    ContentUnavailableView.search(text: trimmedSearch)
                        .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Mode code or description")
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .navigationTitle("Mode")
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

    private var allFilteredEmpty: Bool {
        ADIFCatalog.ModeCategory.allCases.allSatisfy { filteredModes(in: $0).isEmpty }
    }

    private var customEntrySection: some View {
        Section {
            HStack {
                TextField("Custom mode code", text: $customText)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button("Use") {
                    commitCustomEntry()
                }
                .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Custom")
        } footer: {
            Text("Use this for obscure or proprietary modes not in the ADIF catalog.")
        }
    }

    private func modeRow(_ mode: ADIFCatalog.Mode) -> some View {
        Button {
            onSelect(mode.code)
        } label: {
            HStack(spacing: 12) {
                Text(mode.code)
                    .font(.body.monospaced().weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 80, alignment: .leading)

                Text(mode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if mode.code.uppercased() == currentCode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filteredModes(in category: ADIFCatalog.ModeCategory) -> [ADIFCatalog.Mode] {
        let query = trimmedSearch.lowercased()
        return ADIFCatalog.modes
            .filter { $0.category == category }
            .filter { mode in
                guard !query.isEmpty else {
                    return true
                }
                return mode.code.lowercased().contains(query)
                    || mode.description.lowercased().contains(query)
            }
    }

    private func commitCustomEntry() {
        let trimmed = customText.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return
        }
        onSelect(trimmed)
    }
}

#Preview {
    ModePickerSheet(
        currentCode: "FT8",
        onSelect: { print("Selected: \($0)") },
        onDismiss: {}
    )
}
