import CarrierWaveData
import SwiftUI

// MARK: - Constants

let addNewSentinel = "__add_new__"

// MARK: - EquipmentPickerField

/// Dropdown picker backed by shared EquipmentStorage with "Add..." option.
struct EquipmentPickerField: View {
    // MARK: Internal

    @Binding var selection: String?

    let type: EquipmentType

    var body: some View {
        HStack(spacing: 4) {
            Picker("", selection: $pickerValue) {
                Text("None").tag(String?.none)
                ForEach(items, id: \.self) { item in
                    Text(item).tag(Optional(item))
                }
                Divider()
                Text("Add \(type.displayName)...").tag(Optional(addNewSentinel))
            }
            .labelsHidden()
            .onChange(of: pickerValue) { _, newValue in
                if newValue == addNewSentinel {
                    showAddPopover = true
                    pickerValue = selection
                } else {
                    selection = newValue
                }
            }
            .popover(isPresented: $showAddPopover) {
                addItemPopover
            }

            if selection != nil {
                Button {
                    deleteCurrentItem()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove from saved list")
            }
        }
        .onAppear {
            items = EquipmentStorage.load(for: type)
            pickerValue = selection
        }
    }

    // MARK: Private

    @State private var items: [String] = []
    @State private var pickerValue: String?
    @State private var showAddPopover = false
    @State private var newItemText = ""
    @FocusState private var addFieldFocused: Bool

    private var addItemPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New \(type.displayName)")
                .font(.headline)
            HStack {
                TextField(type.addPrompt, text: $newItemText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .focused($addFieldFocused)
                    .onSubmit { addItem() }
                Button("Add") { addItem() }
                    .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .onAppear {
            newItemText = ""
            addFieldFocused = true
        }
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }
        EquipmentStorage.add(trimmed, for: type)
        items = EquipmentStorage.load(for: type)
        selection = trimmed
        pickerValue = trimmed
        newItemText = ""
        showAddPopover = false
    }

    private func deleteCurrentItem() {
        guard let current = selection else {
            return
        }
        EquipmentStorage.remove(current, for: type)
        items = EquipmentStorage.load(for: type)
        selection = nil
        pickerValue = nil
    }
}
