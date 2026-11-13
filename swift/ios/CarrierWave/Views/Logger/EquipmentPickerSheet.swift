import CarrierWaveData
import SwiftUI

// MARK: - EquipmentPickerSheet

/// Generic picker for selecting equipment from a user-managed list.
/// Parameterized by EquipmentType (antenna, key, mic).
struct EquipmentPickerSheet: View {
    // MARK: Internal

    let equipmentType: EquipmentType

    @Binding var selection: String?

    var body: some View {
        NavigationStack {
            List {
                noneRow

                if !items.isEmpty {
                    savedItemsSection
                }

                addItemSection
            }
            .navigationTitle("Select \(equipmentType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                items = EquipmentStorage.load(for: equipmentType)
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var items: [String] = []
    @State private var newItemName = ""
    @State private var isAddingItem = false
    @FocusState private var addFieldFocused: Bool

    private var noneRow: some View {
        Button {
            selection = nil
            dismiss()
        } label: {
            HStack {
                Text("None")
                    .foregroundStyle(.primary)
                Spacer()
                if selection == nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var savedItemsSection: some View {
        Section("Saved \(equipmentType.displayName)s") {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                    dismiss()
                } label: {
                    HStack {
                        Text(item)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == item {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var addItemSection: some View {
        Section {
            if isAddingItem {
                HStack {
                    TextField(equipmentType.addPrompt, text: $newItemName)
                        .textInputAutocapitalization(.words)
                        .focused($addFieldFocused)
                        .onSubmit { addItem() }

                    Button("Add") { addItem() }
                        .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button {
                    isAddingItem = true
                    addFieldFocused = true
                } label: {
                    Label("Add \(equipmentType.displayName)", systemImage: "plus.circle")
                }
            }
        }
    }

    private func addItem() {
        let trimmed = newItemName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }
        EquipmentStorage.add(trimmed, for: equipmentType)
        items = EquipmentStorage.load(for: equipmentType)
        selection = trimmed
        newItemName = ""
        isAddingItem = false
    }

    private func deleteItem(_ item: String) {
        EquipmentStorage.remove(item, for: equipmentType)
        items = EquipmentStorage.load(for: equipmentType)
        if selection == item {
            selection = nil
        }
    }
}
