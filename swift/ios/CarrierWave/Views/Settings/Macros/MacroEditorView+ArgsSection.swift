import CarrierWaveData
import SwiftUI

// MARK: - MacroEditorView+ArgsSection

extension MacroEditorView {
    var argsSection: some View {
        Section {
            if model.spec.args.isEmpty {
                Text("No arguments declared. Add one if your macro needs " +
                    "runtime input (frequency, mode, etc.).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.spec.args) { arg in
                    MacroArgRow(arg: arg)
                        .contentShape(Rectangle())
                        .onTapGesture { editArgTarget = arg }
                }
                .onDelete(perform: deleteArgs)
                .onMove(perform: moveArgs)
            }

            Button {
                addArgDraft = MacroDraftArg()
            } label: {
                Label("Add Argument", systemImage: "plus.circle")
            }
        } header: {
            Text("Arguments")
        } footer: {
            Text("Arguments are typed inputs the macro asks for at run time. " +
                "Use {arg.name} in steps to substitute them.")
        }
        .sheet(item: $addArgDraft) { draft in
            NavigationStack {
                MacroAddArgSheet(draft: draft) { newArg in
                    model.spec.args.append(newArg)
                    model.markDirty()
                }
            }
        }
        .sheet(item: $editArgTarget) { arg in
            NavigationStack {
                MacroEditArgSheet(arg: arg) { updated in
                    if let index = model.spec.args.firstIndex(where: { $0.id == arg.id }) {
                        model.spec.args[index] = updated
                        model.markDirty()
                    }
                }
            }
        }
    }

    private func deleteArgs(_ indices: IndexSet) {
        model.spec.args.remove(atOffsets: indices)
        model.markDirty()
    }

    private func moveArgs(from source: IndexSet, to destination: Int) {
        model.spec.args.move(fromOffsets: source, toOffset: destination)
        model.markDirty()
    }
}

// MARK: - MacroArgRow

struct MacroArgRow: View {
    // MARK: Internal

    let arg: RadioMacroArg

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(arg.label ?? arg.name)
                    .font(.body)
                HStack(spacing: 4) {
                    Text(arg.type.displayName)
                    if let defaultValue = arg.defaultValue {
                        Text("· default \(defaultValue)")
                    }
                    if arg.min != nil || arg.max != nil {
                        Text("· \(arg.min.map(String.init) ?? "-")…\(arg.max.map(String.init) ?? "-")")
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Private

    private var icon: String {
        switch arg.type {
        case .bool: "switch.2"
        case .enumeration: "list.bullet"
        case .uint8,
             .uint16,
             .uint32,
             .uint64: "number"
        case .freqHz,
             .frequency: "dial.high"
        case .string: "textformat"
        }
    }
}

// MARK: - MacroDraftArg

/// Mutable scratch form for the add-arg sheet. Lifted out of
/// `RadioMacroArg` so the sheet can collect partial input without
/// requiring all fields to be valid upfront.
@Observable
@MainActor
final class MacroDraftArg: Identifiable {
    // MARK: Internal

    var name: String = ""
    var label: String = ""
    var type: RadioCommandParamType = .string
    var defaultValue: String = ""
    var minValue: String = ""
    var maxValue: String = ""

    nonisolated let id = UUID()

    func toArg() -> RadioMacroArg? {
        guard !name.isEmpty else {
            return nil
        }
        return RadioMacroArg(
            name: cleanedName,
            label: label.isEmpty ? nil : label,
            type: type,
            values: nil,
            min: Int(minValue),
            max: Int(maxValue),
            defaultValue: defaultValue.isEmpty ? nil : defaultValue
        )
    }

    // MARK: Private

    private var cleanedName: String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

// MARK: - MacroAddArgSheet

struct MacroAddArgSheet: View {
    // MARK: Internal

    @Bindable var draft: MacroDraftArg

    let onSave: (RadioMacroArg) -> Void

    var body: some View {
        Form {
            Section("Name") {
                TextField("frequency", text: $draft.name)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Display label (optional)", text: $draft.label)
            }
            Section("Type") {
                Picker("Type", selection: $draft.type) {
                    ForEach(MacroArgTypeChoice.allCases, id: \.rawValue) { choice in
                        Text(choice.title).tag(choice.type)
                    }
                }
                .pickerStyle(.menu)
                Text(draft.type.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Default value (optional)") {
                TextField(draft.type.placeholder, text: $draft.defaultValue)
                    .keyboardType(draft.type.keyboardType)
            }
            if draft.type.acceptsBounds {
                Section("Bounds") {
                    TextField("Minimum", text: $draft.minValue)
                        .keyboardType(.numberPad)
                    TextField("Maximum", text: $draft.maxValue)
                        .keyboardType(.numberPad)
                    if draft.type == .frequency {
                        Text("Frequency arguments must declare min and max " +
                            "(in Hz) or the verifier blocks save.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Add Argument")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    if let arg = draft.toArg() {
                        onSave(arg)
                        dismiss()
                    }
                }
                .disabled(draft.toArg() == nil)
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}

// MARK: - MacroEditArgSheet

struct MacroEditArgSheet: View {
    // MARK: Lifecycle

    init(arg: RadioMacroArg, onSave: @escaping (RadioMacroArg) -> Void) {
        self.arg = arg
        self.onSave = onSave
        let seed = MacroDraftArg()
        seed.name = arg.name
        seed.label = arg.label ?? ""
        seed.type = arg.type
        seed.defaultValue = arg.defaultValue ?? ""
        seed.minValue = arg.min.map(String.init) ?? ""
        seed.maxValue = arg.max.map(String.init) ?? ""
        _draft = State(wrappedValue: seed)
    }

    // MARK: Internal

    let arg: RadioMacroArg
    let onSave: (RadioMacroArg) -> Void

    var body: some View {
        MacroAddArgSheet(draft: draft, onSave: onSave)
            .navigationTitle("Edit Argument")
    }

    // MARK: Private

    @State private var draft: MacroDraftArg
    @Environment(\.dismiss) private var dismiss
}

// MARK: - MacroArgTypeChoice

enum MacroArgTypeChoice: String, CaseIterable {
    case string
    case bool
    case uint
    case frequency
    case enumeration

    // MARK: Internal

    var title: String {
        switch self {
        case .string: "Text"
        case .bool: "True/False"
        case .uint: "Integer"
        case .frequency: "Frequency (Hz)"
        case .enumeration: "Choice"
        }
    }

    var type: RadioCommandParamType {
        switch self {
        case .string: .string
        case .bool: .bool
        case .uint: .uint64
        case .frequency: .frequency
        case .enumeration: .enumeration
        }
    }
}

// MARK: - RadioCommandParamType UI helpers

extension RadioCommandParamType {
    var keyboardType: UIKeyboardType {
        switch self {
        case .uint8,
             .uint16,
             .uint32,
             .uint64,
             .freqHz,
             .frequency: .numberPad
        case .bool,
             .enumeration,
             .string: .default
        }
    }

    var placeholder: String {
        switch self {
        case .bool: "true / false"
        case .enumeration: "(one of the values)"
        case .uint8,
             .uint16,
             .uint32,
             .uint64: "0"
        case .freqHz,
             .frequency: "14074000"
        case .string: "text"
        }
    }

    var acceptsBounds: Bool {
        switch self {
        case .uint8,
             .uint16,
             .uint32,
             .uint64,
             .freqHz,
             .frequency: true
        case .bool,
             .enumeration,
             .string: false
        }
    }

    var helpText: String {
        switch self {
        case .bool: "User picks true or false."
        case .enumeration: "Enum support ships later — choose Text for now."
        case .uint8: "Whole number 0…255."
        case .uint16: "Whole number 0…65,535."
        case .uint32: "Whole number 0…2³²."
        case .uint64: "Whole number, unsigned."
        case .freqHz,
             .frequency: "User picks a frequency. Bounds are mandatory."
        case .string: "User types arbitrary text."
        }
    }
}
