import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - GearComponentMenu

/// One inline equipment slot (Radio / Antenna / Key / Mic) in the Gear section.
/// The row is a pull-down `Menu` of the user's inventory for the category, plus
/// "Add new…" and "None". Adding is fully inline: "Add new…" expands a search
/// field right in the form whose debounced results (Rust catalog search) are
/// tappable — no sheet, no navigation. Selecting or adding routes the chosen
/// snapshot back through `onSelect` so the wizard can capture `radioItemID` and
/// refresh connectors, and keeps CW-Sweep KVS in sync.
struct GearComponentMenu: View {
    // MARK: Internal

    let category: EquipmentCategory
    @Binding var selection: String?

    var inventory: EquipmentInventoryModel
    /// Whether this slot applies to the current mode (Key for CW, Mic for phone).
    /// Dimmed but still usable when false.
    var enabled = true
    /// Delivers the resolved snapshot after a change (`nil` for "None").
    var onSelect: (EquipmentInventorySnapshot?) -> Void = { _ in }

    var body: some View {
        menuRow
        if editing {
            addEditorRows
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var editing = false
    @State private var query = ""
    @State private var matches: [FfiCatalogMatch] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var working = false

    private var label: String {
        category.displayName
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var menuRow: some View {
        Menu {
            let items = inventory.items(for: category)
            if !items.isEmpty {
                Section("My \(label)s") {
                    ForEach(items) { item in
                        Button {
                            select(item)
                        } label: {
                            if selection == item.displayName {
                                Label(item.displayName, systemImage: "checkmark")
                            } else {
                                Text(item.displayName)
                            }
                        }
                    }
                }
            }
            Button {
                beginAdd()
            } label: {
                Label("Add new \(label.lowercased())…", systemImage: "plus.circle")
            }
            Button {
                selection = nil
                onSelect(nil)
            } label: {
                Text("None")
            }
        } label: {
            rowLabel
        }
        .disabled(!enabled)
    }

    private var rowLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .foregroundStyle(Color.purple)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(selection ?? "None")
                .foregroundStyle(selection != nil ? Color.purple : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(Color.purple)
        }
        .contentShape(Rectangle())
        .opacity(enabled ? 1 : 0.4)
    }

    @ViewBuilder
    private var addEditorRows: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("New \(label.lowercased()) name", text: $query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            if working {
                ProgressView().controlSize(.mini)
            } else {
                Button {
                    cancelAdd()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }

        ForEach(matches, id: \.entry.id) { match in
            Button {
                Task { await addFromCatalog(match.entry) }
            } label: {
                catalogRow(match.entry)
            }
            .buttonStyle(.plain)
            .disabled(working)
        }

        if !trimmedQuery.isEmpty {
            Button {
                Task { await addCustom() }
            } label: {
                Label("Add “\(trimmedQuery)” as custom \(label.lowercased())", systemImage: "plus")
                    .font(.subheadline)
            }
            .disabled(working)
        }
    }

    private func catalogRow(_ entry: FfiEquipmentCatalogEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.manufacturer.map { "\($0) \(entry.name)" } ?? entry.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let power = entry.maxPowerWatts {
                    Text("\(Int(power))W")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("Add")
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
        }
        .contentShape(Rectangle())
    }

    private func select(_ item: EquipmentInventorySnapshot) {
        selection = item.displayName
        onSelect(item)
    }

    private func beginAdd() {
        editing = true
        query = ""
        matches = []
    }

    private func cancelAdd() {
        searchTask?.cancel()
        editing = false
        query = ""
        matches = []
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            matches = []
            return
        }
        searchTask = Task {
            // Debounce — local search, but keep keystrokes cheap.
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled {
                return
            }
            let results = await Equipment.searchCatalog(trimmed, category: category)
            if !Task.isCancelled {
                matches = results
            }
        }
    }

    private func addFromCatalog(_ entry: FfiEquipmentCatalogEntry) async {
        working = true
        defer { working = false }
        guard let item = try? await Equipment.addCatalogItem(entry.id) else {
            return
        }
        await finishAdd(item)
    }

    private func addCustom() async {
        working = true
        defer { working = false }
        let name = trimmedQuery
        guard !name.isEmpty else {
            return
        }
        let input = FfiCustomEquipmentInput(
            name: name,
            category: category.rawValue,
            manufacturer: nil,
            bands: [],
            modes: [],
            maxPower: nil,
            portability: "portable"
        )
        guard let item = try? await Equipment.addCustomItem(input) else {
            return
        }
        await finishAdd(item)
    }

    /// After an add: mirror into SwiftData (id-matched, so legacy readers stay
    /// consistent), refresh inventory, select the new item, publish KVS, close.
    private func finishAdd(_ item: FfiEquipmentItem) async {
        let snapshot = EquipmentInventorySnapshot(ffi: item)
        modelContext.insert(EquipmentItem(ffiMirror: item))
        try? modelContext.save()
        await inventory.reload()
        selection = snapshot.displayName
        onSelect(snapshot)
        EquipmentInventorySync.pushSnapshotsToKVS(
            category: category,
            snapshots: inventory.items(for: category)
        )
        editing = false
        query = ""
        matches = []
    }
}
