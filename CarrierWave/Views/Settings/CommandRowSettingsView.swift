// Command Row Settings View
//
// Configures which commands appear in the optional second row
// of the keyboard accessory in the logger.

import CarrierWaveCore
import SwiftUI

// MARK: - Notification Name Extension

extension Notification.Name {
    static let commandRowConfigurationChanged = Notification.Name(
        "commandRowConfigurationChanged"
    )
}

// MARK: - CommandRowItem

/// Represents a configurable command for the keyboard accessory row
enum CommandRowItem: String, CaseIterable {
    case rbn
    case pota
    case p2p
    case solar
    case weather
    case spot
    case map
    case manual
    case help

    // MARK: Internal

    var label: String {
        switch self {
        case .rbn: "RBN"
        case .pota: "POTA"
        case .p2p: "P2P"
        case .solar: "SOLAR"
        case .weather: "WX"
        case .spot: "SPOT"
        case .map: "MAP"
        case .manual: "MANUAL"
        case .help: "HELP"
        }
    }

    var icon: String {
        switch self {
        case .rbn: "dot.radiowaves.up.forward"
        case .pota: "tree.fill"
        case .p2p: "arrow.left.arrow.right"
        case .solar: "sun.max"
        case .weather: "cloud.sun"
        case .spot: "mappin.and.ellipse"
        case .map: "map"
        case .manual: "book.closed"
        case .help: "questionmark.circle"
        }
    }

    var description: String {
        switch self {
        case .rbn: "Show RBN spots"
        case .pota: "Show POTA activator spots"
        case .p2p: "Find park-to-park opportunities"
        case .solar: "Show solar conditions"
        case .weather: "Show weather conditions"
        case .spot: "Self-spot to POTA"
        case .map: "Show session QSO map"
        case .manual: "Open radio manual"
        case .help: "Show command help"
        }
    }

    var command: LoggerCommand {
        switch self {
        case .rbn: .rbn(callsign: nil)
        case .pota: .pota
        case .p2p: .p2p
        case .solar: .solar
        case .weather: .weather
        case .spot: .spot(comment: nil)
        case .map: .map
        case .manual: .manual
        case .help: .help
        }
    }
}

// MARK: - CommandRowSettingsView

struct CommandRowSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            previewSection
            enableToggleSection
            if commandRowEnabled {
                enabledCommandsSection
                availableCommandsSection
            }
            resetSection
        }
        .navigationTitle("Command Row")
        .environment(\.editMode, .constant(.active))
        .onAppear {
            refreshCommands()
        }
    }

    // MARK: Private

    private static let defaultCommands = "rbn,solar,weather,spot,pota,p2p"

    @AppStorage("commandRowEnabled") private var commandRowEnabled = false
    @AppStorage("commandRowCommands") private var commandsString = defaultCommands

    @State private var enabledCommands: [CommandRowItem] = []
    @State private var availableCommands: [CommandRowItem] = []

    private var previewSection: some View {
        Section {
            CommandRowPreview(
                enabled: commandRowEnabled,
                commands: enabledCommands
            )
        } header: {
            Text("Preview")
        }
    }

    private var enableToggleSection: some View {
        Section {
            Toggle("Show Command Row", isOn: $commandRowEnabled)
                .onChange(of: commandRowEnabled) { _, _ in
                    notifyChange()
                }
        } footer: {
            Text("Command row appears below the number row in the logger keyboard.")
        }
    }

    private var enabledCommandsSection: some View {
        Section {
            if enabledCommands.isEmpty {
                Text("No commands enabled")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(enabledCommands, id: \.self) { item in
                    commandRow(item, enabled: true)
                }
                .onMove(perform: moveEnabledCommand)
            }
        } header: {
            Text("Enabled Commands")
        } footer: {
            Text("Drag to reorder. Tap to disable.")
        }
    }

    private var availableCommandsSection: some View {
        Section {
            if availableCommands.isEmpty {
                Text("All commands enabled")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableCommands, id: \.self) { item in
                    commandRow(item, enabled: false)
                }
            }
        } header: {
            Text("Available Commands")
        } footer: {
            Text("Tap to enable.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                commandRowEnabled = false
                commandsString = Self.defaultCommands
                refreshCommands()
            }
        }
    }

    private func commandRow(_ item: CommandRowItem, enabled: Bool) -> some View {
        Button {
            toggleCommand(item, enabled: enabled)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(enabled ? .primary : .secondary)
                    Text(item.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: enabled ? "minus.circle" : "plus.circle")
                    .foregroundStyle(enabled ? .red : .green)
            }
        }
        .buttonStyle(.plain)
    }

    private func refreshCommands() {
        let keys = commandsString.isEmpty ? [] : commandsString.components(separatedBy: ",")
        enabledCommands = keys.compactMap { CommandRowItem(rawValue: $0) }
        availableCommands = CommandRowItem.allCases.filter { !enabledCommands.contains($0) }
    }

    private func saveCommands() {
        commandsString = enabledCommands.map(\.rawValue).joined(separator: ",")
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .commandRowConfigurationChanged, object: nil)
    }

    private func toggleCommand(_ item: CommandRowItem, enabled: Bool) {
        if enabled {
            enabledCommands.removeAll { $0 == item }
            availableCommands.append(item)
            // Sort available by the standard order
            availableCommands.sort {
                CommandRowItem.allCases.firstIndex(of: $0)!
                    < CommandRowItem.allCases.firstIndex(of: $1)!
            }
        } else {
            availableCommands.removeAll { $0 == item }
            enabledCommands.append(item)
        }
        saveCommands()
    }

    private func moveEnabledCommand(from source: IndexSet, to destination: Int) {
        enabledCommands.move(fromOffsets: source, toOffset: destination)
        saveCommands()
    }
}

// MARK: - CommandRowPreview

struct CommandRowPreview: View {
    // MARK: Internal

    let enabled: Bool
    let commands: [CommandRowItem]

    var body: some View {
        if enabled, !commands.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(commands, id: \.self) { item in
                        previewButton(item)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            Text("Command row disabled")
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    // MARK: Private

    private func previewButton(_ item: CommandRowItem) -> some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
            Text(item.label)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.15))
        .foregroundStyle(.purple)
        .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        CommandRowSettingsView()
    }
}
