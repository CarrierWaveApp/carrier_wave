import CarrierWaveCore
import SwiftUI

// MARK: - CommandPaletteView

/// VS Code / Raycast-style command palette (Cmd+K)
struct CommandPaletteView: View {
    // MARK: Internal

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
            CommandMatch(icon: "square.and.pencil", title: "Focus Logger", shortcut: "Cmd+L") {},
            CommandMatch(icon: "play.circle", title: "Start Session", shortcut: nil) {},
            CommandMatch(icon: "stop.circle", title: "End Session", shortcut: nil) {},
            CommandMatch(icon: "dot.radiowaves.right", title: "Self-Spot", shortcut: nil) {},
            CommandMatch(icon: "arrow.triangle.2.circlepath", title: "Sync Now", shortcut: nil) {},
            CommandMatch(icon: "sidebar.leading", title: "Toggle Sidebar", shortcut: "Cmd+0") {},
            CommandMatch(icon: "sidebar.trailing", title: "Toggle Inspector", shortcut: "Cmd+Opt+I") {},
        ]
    }

    private var matchingCommands: [CommandMatch] {
        let query = searchText.lowercased()
        return allCommands.filter { $0.title.lowercased().contains(query) }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        List {
            Section("Quick Actions") {
                CommandRow(icon: "square.and.pencil", title: "Focus Logger", shortcut: "Cmd+L") {
                    dismiss()
                }
                CommandRow(icon: "play.circle", title: "Start Session", shortcut: nil) {
                    dismiss()
                }
                CommandRow(icon: "antenna.radiowaves.left.and.right", title: "Tune Radio", shortcut: nil) {
                    dismiss()
                }
                CommandRow(icon: "dot.radiowaves.right", title: "Self-Spot", shortcut: nil) {
                    dismiss()
                }
            }

            Section("Roles") {
                ForEach(OperatingRole.allCases) { role in
                    CommandRow(icon: role.icon, title: role.displayName, shortcut: "Cmd+\(role.keyboardShortcut)") {
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

    private func executeTopResult() {
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
