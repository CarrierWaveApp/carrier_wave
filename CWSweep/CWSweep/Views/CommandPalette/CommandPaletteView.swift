import CarrierWaveCore
import SwiftUI

// MARK: - CommandPaletteView

/// VS Code / Raycast-style command palette (Cmd+K)
struct CommandPaletteView: View {
    // MARK: Internal

    /// Callback to switch to the radio command palette
    var onSwitchToRadioPalette: (() -> Void)?

    /// Callbacks for workspace actions that need to mutate parent state
    var onSelectSidebarItem: ((SidebarItem) -> Void)?
    var onSetRole: ((OperatingRole) -> Void)?
    var onToggleInspector: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Type a command, callsign, or frequency...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { executeTopResult() }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
            }
            .padding()

            Divider()

            // Results
            if searchText.isEmpty {
                quickActions
            } else if searchText.hasPrefix(">") {
                radioBridgeView
            } else {
                filteredResults
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 300, idealHeight: 400)
    }

    // MARK: Private

    // MARK: - Command Matching

    private struct CommandMatch {
        let icon: String
        let title: String
        let shortcut: String?
        let action: () -> Void
    }

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(RadioManager.self) private var radioManager

    private var allCommands: [CommandMatch] {
        [
            CommandMatch(icon: "square.and.pencil", title: "Focus Logger", shortcut: nil) {
                onSelectSidebarItem?(.logger)
            },
            CommandMatch(icon: "play.circle", title: "Start Session", shortcut: nil) {
                onSelectSidebarItem?(.sessions)
            },
            CommandMatch(icon: "stop.circle", title: "End Session", shortcut: nil) {
                onSelectSidebarItem?(.sessions)
            },
            CommandMatch(icon: "antenna.radiowaves.left.and.right", title: "Tune Radio", shortcut: "Cmd+Shift+P") {
                onSwitchToRadioPalette?()
            },
            CommandMatch(icon: "arrow.triangle.2.circlepath", title: "Sync Now", shortcut: nil) {
                Task { await CloudSyncService.shared.syncPending() }
            },
            CommandMatch(icon: "sidebar.trailing", title: "Toggle Inspector", shortcut: "Cmd+Opt+I") {
                onToggleInspector?()
            },
            CommandMatch(icon: "antenna.radiowaves.left.and.right", title: "Radio Settings", shortcut: nil) {
                onSelectSidebarItem?(.radio)
            },
            CommandMatch(icon: "chart.bar", title: "Dashboard", shortcut: nil) {
                onSelectSidebarItem?(.dashboard)
            },
            CommandMatch(icon: "list.bullet.rectangle", title: "QSO Log", shortcut: nil) {
                onSelectSidebarItem?(.qsoLog)
            },
            CommandMatch(icon: "mappin.and.ellipse", title: "Spots", shortcut: nil) {
                onSelectSidebarItem?(.spots)
            },
            CommandMatch(icon: "map", title: "Band Map", shortcut: nil) {
                onSelectSidebarItem?(.bandMap)
            },
        ]
    }

    private var matchingCommands: [CommandMatch] {
        let query = searchText.lowercased()
        return allCommands.filter { $0.title.lowercased().contains(query) }
    }

    private var navigableSidebarItems: [(item: SidebarItem, icon: String)] {
        [
            (.logger, "square.and.pencil"),
            (.spots, "mappin.and.ellipse"),
            (.bandMap, "map"),
            (.cluster, "network"),
            (.dashboard, "chart.bar"),
            (.qsoLog, "list.bullet.rectangle"),
            (.sessions, "clock"),
            (.radio, "antenna.radiowaves.left.and.right"),
            (.sync, "arrow.triangle.2.circlepath"),
        ]
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        List {
            Section("Help") {
                helpRow("callsign", "Look up a callsign (e.g. K4ABC)")
                helpRow("frequency", "Tune radio (e.g. 14074 or 14.074)")
                helpRow("park ref", "Search park (e.g. K-0001)")
                helpRow("> ...", "Switch to Radio Palette")
            }

            Section("Quick Actions") {
                CommandRow(icon: "square.and.pencil", title: "Focus Logger", shortcut: "Cmd+L") {
                    onSelectSidebarItem?(.logger)
                    dismiss()
                }
                CommandRow(icon: "antenna.radiowaves.left.and.right", title: "Tune Radio", shortcut: "Cmd+Shift+P") {
                    dismiss()
                    onSwitchToRadioPalette?()
                }
                CommandRow(icon: "arrow.triangle.2.circlepath", title: "Sync Now", shortcut: nil) {
                    Task { await CloudSyncService.shared.syncPending() }
                    dismiss()
                }
                CommandRow(icon: "sidebar.trailing", title: "Toggle Inspector", shortcut: "Cmd+Opt+I") {
                    onToggleInspector?()
                    dismiss()
                }
            }

            Section("Navigate") {
                ForEach(navigableSidebarItems, id: \.item) { entry in
                    CommandRow(icon: entry.icon, title: entry.item.displayName, shortcut: nil) {
                        onSelectSidebarItem?(entry.item)
                        dismiss()
                    }
                }
            }

            Section("Roles") {
                ForEach(OperatingRole.allCases) { role in
                    CommandRow(icon: role.icon, title: role.displayName, shortcut: "Cmd+\(role.keyboardShortcut)") {
                        onSetRole?(role)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Filtered Results

    private var filteredResults: some View {
        List {
            let results = matchingCommands
            if results.isEmpty {
                // Check if it looks like a frequency
                if let freq = parseFrequency(searchText) {
                    Section("Tune Radio") {
                        CommandRow(icon: "antenna.radiowaves.left.and.right",
                                   title: "Tune to \(String(format: "%.3f", freq)) MHz",
                                   shortcut: nil)
                        {
                            Task {
                                try? await radioManager.tuneToFrequency(freq)
                            }
                            dismiss()
                        }
                    }
                }

                // Check if it looks like a callsign
                if CallsignDetector.detectPrimaryCallsign(from: searchText.uppercased()) != nil {
                    Section("Callsign") {
                        CommandRow(icon: "person.circle", title: "Lookup \(searchText.uppercased())", shortcut: nil) {
                            dismiss()
                        }
                    }
                }

                // Check if it looks like a park reference
                if QuickEntryParser.isParkReference(searchText.uppercased()) {
                    Section("Park") {
                        CommandRow(icon: "leaf", title: "Search \(searchText.uppercased())", shortcut: nil) {
                            dismiss()
                        }
                    }
                }

                if CallsignDetector.detectPrimaryCallsign(from: searchText.uppercased()) == nil,
                   parseFrequency(searchText) == nil,
                   !QuickEntryParser.isParkReference(searchText.uppercased())
                {
                    Text("No results for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Commands") {
                    ForEach(results, id: \.title) { result in
                        CommandRow(icon: result.icon, title: result.title, shortcut: result.shortcut) {
                            result.action()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var radioBridgeView: some View {
        VStack(spacing: 12) {
            Text("Switch to Radio Palette")
                .font(.headline)
            Text("Press Enter to open the radio command palette (Cmd+Shift+P)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("Enter")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Text("Switch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    private func helpRow(_ command: String, _ description: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func executeTopResult() {
        if searchText.hasPrefix(">") {
            dismiss()
            onSwitchToRadioPalette?()
            return
        }

        let results = matchingCommands
        if let first = results.first {
            first.action()
            dismiss()
            return
        }

        // Try frequency
        if let freq = parseFrequency(searchText) {
            Task { try? await radioManager.tuneToFrequency(freq) }
            dismiss()
            return
        }

        dismiss()
    }

    private func parseFrequency(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        // Accept kHz (e.g., 14074) or MHz (e.g., 14.074)
        if value > 1_000 {
            return value / 1_000.0 // kHz to MHz
        } else if value > 1, value < 500 {
            return value // Already MHz
        }
        return nil
    }
}

// MARK: - CommandRow

struct CommandRow: View {
    let icon: String
    let title: String
    let shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
