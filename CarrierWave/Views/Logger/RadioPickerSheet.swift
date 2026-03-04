import CarrierWaveData
import SwiftUI

// MARK: - RadioStorage

/// Simple UserDefaults-backed storage for the user's radio list
enum RadioStorage {
    // MARK: Internal

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ radios: [String]) {
        UserDefaults.standard.set(radios, forKey: key)
    }

    static func add(_ name: String) {
        var radios = load()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !radios.contains(trimmed) else {
            return
        }
        radios.append(trimmed)
        radios.sort(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        save(radios)
    }

    static func remove(_ name: String) {
        var radios = load()
        radios.removeAll { $0 == name }
        save(radios)
    }

    // MARK: Private

    private static let key = "userRadioList"
}

// MARK: - RadioPickerSheet

/// Sheet for selecting a radio from the user's saved list, with inline add/delete
struct RadioPickerSheet: View {
    // MARK: Internal

    @Binding var selection: String?

    var body: some View {
        NavigationStack {
            List {
                noneRow

                if !radios.isEmpty {
                    savedRadiosSection
                }

                addRadioSection
            }
            .navigationTitle("Select Radio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                radios = RadioStorage.load()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var radios: [String] = []
    @State private var newRadioName = ""
    @State private var isAddingRadio = false
    @FocusState private var addFieldFocused: Bool

    // MARK: - Sections

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

    private var savedRadiosSection: some View {
        Section("Saved Radios") {
            ForEach(radios, id: \.self) { radio in
                Button {
                    selection = radio
                    dismiss()
                } label: {
                    HStack {
                        Text(radio)
                            .foregroundStyle(.primary)
                        Spacer()
                        if FieldGuideLinker.hasManual(for: radio) {
                            Button {
                                FieldGuideLinker.openManual(for: radio)
                            } label: {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        if selection == radio {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteRadio(radio)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var addRadioSection: some View {
        Section {
            if isAddingRadio {
                HStack {
                    TextField("Radio name", text: $newRadioName)
                        .textInputAutocapitalization(.words)
                        .focused($addFieldFocused)
                        .onSubmit { addRadio() }

                    Button("Add") { addRadio() }
                        .disabled(newRadioName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button {
                    isAddingRadio = true
                    addFieldFocused = true
                } label: {
                    Label("Add Radio", systemImage: "plus.circle")
                }
            }
        }
    }

    private func addRadio() {
        let trimmed = newRadioName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }
        RadioStorage.add(trimmed)
        radios = RadioStorage.load()
        selection = trimmed
        newRadioName = ""
        isAddingRadio = false
    }

    private func deleteRadio(_ radio: String) {
        RadioStorage.remove(radio)
        radios = RadioStorage.load()
        if selection == radio {
            selection = nil
        }
    }
}
