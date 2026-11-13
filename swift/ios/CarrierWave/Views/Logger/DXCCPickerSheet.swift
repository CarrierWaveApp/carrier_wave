import CarrierWaveCore
import SwiftUI

// MARK: - DXCCPickerSheet

/// Sheet for selecting a DXCC entity by name, prefix, or number.
/// Backed by `DescriptionLookup.numberLookup`, so the catalog is always in sync
/// with the rest of the app. Supports a custom-entry escape hatch for entities
/// that aren't in our bundled list yet (e.g. freshly-added or deleted entities
/// the user still wants to log historically).
struct DXCCPickerSheet: View {
    // MARK: Lifecycle

    init(
        currentNumber: Int?,
        onSelect: @escaping (DXCCEntityRef) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.currentNumber = currentNumber
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    // MARK: Internal

    let currentNumber: Int?
    let onSelect: (DXCCEntityRef) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                customEntrySection
                entityListSection
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Number, name, or prefix")
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .navigationTitle("DXCC Entity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }

    // MARK: Private

    /// Sorted, deduplicated list of every DXCC entity we ship with.
    private static let allEntities: [DXCCEntityRef] = DescriptionLookup.numberLookup.values
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    /// Prefixes grouped by entity number, so we can match "KH6" → Hawaii.
    private static let prefixesByNumber: [Int: [String]] = {
        var result: [Int: [String]] = [:]
        for (prefixes, entity) in DescriptionLookup.dxccEntities {
            result[entity.number, default: []].append(contentsOf: prefixes)
        }
        return result
    }()

    @State private var searchText = ""
    @State private var customNumberText = ""
    @State private var customNameText = ""

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var filteredEntities: [DXCCEntityRef] {
        let query = trimmedSearch
        guard !query.isEmpty else {
            return Self.allEntities
        }

        let lower = query.lowercased()
        if let number = Int(query) {
            return Self.allEntities.filter {
                $0.number == number
                    || String($0.number).contains(query)
                    || $0.name.lowercased().contains(lower)
            }
        }

        return Self.allEntities.filter { entity in
            if entity.name.lowercased().contains(lower) {
                return true
            }
            let prefixes = Self.prefixesByNumber[entity.number] ?? []
            return prefixes.contains { $0.lowercased().contains(lower) }
        }
    }

    private var canCommitCustomEntry: Bool {
        guard let number = Int(customNumberText.trimmingCharacters(in: .whitespaces)),
              number > 0
        else {
            return false
        }
        return !customNameText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var customEntrySection: some View {
        Section {
            HStack {
                TextField("Number", text: $customNumberText)
                    .keyboardType(.numberPad)
                    .font(.body.monospaced())
                    .frame(maxWidth: 100)

                Divider()

                TextField("Entity name", text: $customNameText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            Button {
                commitCustomEntry()
            } label: {
                HStack {
                    Label("Use Custom Entry", systemImage: "pencil")
                    Spacer()
                }
            }
            .disabled(!canCommitCustomEntry)
        } header: {
            Text("Custom")
        } footer: {
            Text(
                "Use this if the entity isn't in the bundled list — " +
                    "e.g. recently added, deleted, or a non-DXCC ARRL field-day entity."
            )
        }
    }

    private var entityListSection: some View {
        Section {
            let entities = filteredEntities
            if entities.isEmpty {
                ContentUnavailableView.search(text: trimmedSearch)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(entities, id: \.number) { entity in
                    entityRow(entity)
                }
            }
        } header: {
            Text("All Entities (\(Self.allEntities.count))")
        }
    }

    private func entityRow(_ entity: DXCCEntityRef) -> some View {
        Button {
            onSelect(entity)
        } label: {
            HStack(spacing: 12) {
                Text(String(entity.number))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    if let prefixes = Self.prefixesByNumber[entity.number], !prefixes.isEmpty {
                        Text(prefixes.prefix(5).joined(separator: ", "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if entity.number == currentNumber {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commitCustomEntry() {
        guard let number = Int(customNumberText.trimmingCharacters(in: .whitespaces)) else {
            return
        }
        let name = customNameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return
        }
        onSelect(DXCCEntityRef(number: number, name: name))
    }
}

#Preview {
    DXCCPickerSheet(
        currentNumber: 291, // USA
        onSelect: { entity in print("Selected: \(entity.name) #\(entity.number)") },
        onDismiss: {}
    )
}
