import CarrierWaveData
import SwiftUI

// MARK: - VendorCommandPickerView

/// Editor for `.vendorCommand(commandId:args:)`. Drives the catalog via
/// `RadioCommandCatalog.shared` and lets the user pick a command and
/// fill in any parameters. Phase 1 collects param values as plain text;
/// the validator runs at execution time.
struct VendorCommandPickerView: View {
    // MARK: Lifecycle

    init(commandId: Binding<String>, args: Binding<[String: String]?>) {
        _commandId = commandId
        _args = args
        _selectedProtocol = State(initialValue: Self.initialProtocol(for: commandId.wrappedValue))
    }

    // MARK: Internal

    @Binding var commandId: String
    @Binding var args: [String: String]?

    var body: some View {
        Form {
            Section("Protocol") {
                Picker("Protocol", selection: $selectedProtocol) {
                    ForEach(RadioCommandProtocol.allCases, id: \.rawValue) { rigProtocol in
                        Text(rigProtocol.displayName).tag(rigProtocol)
                    }
                }
                .pickerStyle(.segmented)
            }

            if availableCommands.isEmpty {
                Section {
                    Text("No catalog commands loaded for \(selectedProtocol.displayName). " +
                        "Catalog ships with bundled vendor sets — check that " +
                        "Resources/RadioCommands contains a .json for this protocol.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                commandSection
                if let selectedCommand {
                    paramsSection(for: selectedCommand)
                }
            }
        }
        .navigationTitle("Vendor Command")
        .onChange(of: commandId) { _, newValue in
            selectedProtocol = Self.initialProtocol(for: newValue)
        }
    }

    // MARK: Private

    @State private var selectedProtocol: RadioCommandProtocol

    private var availableCommands: [RadioCommandSpec] {
        RadioCommandCatalog.shared.commands(forProtocol: selectedProtocol)
    }

    private var selectedCommand: RadioCommandSpec? {
        availableCommands.first { $0.id == commandId }
    }

    private var groupedByCategory: [String: [RadioCommandSpec]] {
        Dictionary(grouping: availableCommands) { $0.category ?? "Other" }
    }

    private var commandSection: some View {
        Section {
            ForEach(groupedByCategory.keys.sorted(), id: \.self) { category in
                DisclosureGroup(category) {
                    ForEach(groupedByCategory[category] ?? []) { command in
                        Button {
                            commandId = command.id
                            seedDefaults(for: command)
                        } label: {
                            commandRow(command, selected: command.id == commandId)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Command")
        } footer: {
            if let selectedCommand {
                Text(selectedCommand.notes ?? "")
                    .font(.caption)
            }
        }
    }

    private func paramsSection(for command: RadioCommandSpec) -> some View {
        Section("Parameters") {
            if command.params.isEmpty {
                Text("No parameters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(command.params) { param in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(param.label ?? param.name)
                            .font(.caption.weight(.semibold))
                        TextField(
                            param.defaultValue ?? param.type.displayName,
                            text: paramBinding(for: param)
                        )
                    }
                }
            }
        }
    }

    private func commandRow(_ command: RadioCommandSpec, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(command.label)
                    .font(.body)
                Text(command.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }

    private static func initialProtocol(for commandId: String) -> RadioCommandProtocol {
        if let command = RadioCommandCatalog.shared.command(id: commandId) {
            return command.rigProtocol
        }
        return .civ
    }

    private func paramBinding(for param: RadioCommandParam) -> Binding<String> {
        Binding(
            get: { args?[param.name] ?? "" },
            set: { newValue in
                var dict = args ?? [:]
                if newValue.isEmpty {
                    dict.removeValue(forKey: param.name)
                } else {
                    dict[param.name] = newValue
                }
                args = dict.isEmpty ? nil : dict
            }
        )
    }

    private func seedDefaults(for command: RadioCommandSpec) {
        var dict = args ?? [:]
        for param in command.params {
            if dict[param.name] == nil, let defaultValue = param.defaultValue {
                dict[param.name] = defaultValue
            }
        }
        args = dict.isEmpty ? nil : dict
    }
}
