import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - RadioPaletteView

/// Radio command palette (Cmd+Shift+P) for direct radio tuning commands
///
/// Parse-and-confirm pattern: user types frequency/mode/split commands,
/// sees real-time parsed feedback, and presses Enter to apply.
struct RadioPaletteView: View {
    // MARK: Internal

    enum HistoryDirection {
        case up
        case down
    }

    /// Callback to switch to the app command palette
    var onSwitchToAppPalette: (() -> Void)?

    @State var searchText = ""
    @State var recentCommands: [String] = RadioPaletteHistory.load()
    @State var historyIndex: Int?
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Environment(RadioManager.self) var radioManager
    @Environment(ClusterManager.self) var clusterManager
    @Environment(ContestManager.self) var contestManager
    @Environment(WinKeyerManager.self) var winKeyerManager
    @AppStorage("myCallsign") var myCallsign = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            inputSection
            Divider()
            contentSection
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(minWidth: 500, idealWidth: 600, minHeight: 280, idealHeight: 360)
    }

    func actionBar(_ command: RadioCommand) -> some View {
        HStack {
            Spacer()
            HStack(spacing: 16) {
                keyHint("Enter", actionLabel(for: command))
                keyHint("Esc", "Cancel")
            }
        }
    }

    func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func actionLabel(for command: RadioCommand) -> String {
        guard let named = command.namedCommand else {
            return "Apply to radio"
        }
        switch named {
        case .lookup: return "Look up"
        case .spot: return "Send spot"
        case .setPark,
             .setSummit: return "Set on session"
        case .setPower: return "Set power"
        case .sendCQ: return "Send CQ"
        case .setSpeed: return "Set speed"
        case .setContestMode: return "Set mode"
        case .findCall,
             .lastQSOs,
             .sessionCount: return "Show"
        }
    }

    // MARK: Private

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Label("Radio", systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.tint.opacity(0.15), in: Capsule())

            Spacer()

            if radioManager.isConnected {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text(FrequencyFormatter.formatWithUnit(radioManager.frequency))
                        .font(.caption.monospacedDigit())
                    if !radioManager.mode.isEmpty {
                        Text(radioManager.mode)
                            .font(.caption.weight(.medium))
                    }
                }
                .foregroundStyle(.secondary)
            } else {
                Text("No radio connected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Input

    private var inputSection: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)

            TextField(
                "e.g. '14074 CW', 'QRZ K4ABC', or 'PARK K-0001'",
                text: $searchText
            )
            .textFieldStyle(.plain)
            .font(.title3.monospacedDigit())
            .onSubmit { executeCommand() }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
            .onKeyPress(.upArrow) {
                navigateHistory(direction: .up)
                return .handled
            }
            .onKeyPress(.downArrow) {
                navigateHistory(direction: .down)
                return .handled
            }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    historyIndex = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    private var contentSection: some View {
        Group {
            if searchText.isEmpty {
                emptyStateView
            } else if searchText.hasPrefix(">") {
                paletteBridgeView
            } else {
                parseResultView
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !recentCommands.isEmpty {
                recentCommandsSection
            }

            syntaxHelpSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentCommandsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(recentCommands.prefix(5), id: \.self) { cmd in
                Button {
                    searchText = cmd
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                        Text(cmd)
                            .font(.body.monospacedDigit())
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var syntaxHelpSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Syntax")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                helpRow("14074", "Tune to 14.074 MHz")
                helpRow("20m FT8", "20m FT8 segment")
                helpRow("CW", "Change mode only")
                helpRow("UP 5", "Split TX +5 kHz")
                helpRow("QRZ K4ABC", "Look up callsign")
                helpRow("SPOT K4ABC", "Spot to cluster")
            }
            Group {
                helpRow("CQ", "Send CQ macro (F1)")
                helpRow("WPM 25", "Set CW speed")
                helpRow("RUN / S&P", "Contest mode toggle")
                helpRow("FIND K4ABC", "Search log")
                helpRow("LAST 10", "Recent QSOs")
                helpRow("COUNT", "Session QSO count")
            }
        }
    }

    // MARK: - Palette Bridge

    private var paletteBridgeView: some View {
        VStack(spacing: 12) {
            Text("Switch to App Palette")
                .font(.headline)
            Text("Press Enter to open the app command palette (Cmd+K)")
                .font(.caption)
                .foregroundStyle(.secondary)
            keyHint("Enter", "Switch")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    // MARK: - Parse Result

    private var parseResultView: some View {
        let expanded = RadioCommandParser.expandAliases(searchText, aliases: RadioAliasStore.load())
        let (command, tokens) = RadioCommandParser.parse(expanded)

        return VStack(alignment: .leading, spacing: 12) {
            if expanded != searchText.trimmingCharacters(in: .whitespaces) {
                aliasIndicator(expanded: expanded)
            }
            if tokens.isEmpty || tokens.allSatisfy({ $0.kind == .unknown }) {
                noParseResult
            } else {
                tokenPills(tokens)
                commandSummary(command)
                actionBar(command)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noParseResult: some View {
        let suggestions = RadioCommandParser.suggestCommands(for: searchText)
        return VStack(spacing: 8) {
            Text("Could not parse command")
                .foregroundStyle(.secondary)
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Did you mean:")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ForEach(suggestions, id: \.self) { cmd in
                        Button { searchText = cmd + " " } label: {
                            Text(cmd)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Try: frequency [mode] [UP/DOWN offset]")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func aliasIndicator(expanded: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.right.circle")
                .font(.caption2)
            Text("Alias → \(expanded)")
                .font(.caption)
        }
        .foregroundStyle(.blue)
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

    private func tokenPills(_ tokens: [RadioParsedToken]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(tokens) { token in
                tokenPill(token)
            }
        }
    }

    private func tokenPill(_ token: RadioParsedToken) -> some View {
        HStack(spacing: 4) {
            Image(systemName: token.kind.icon)
                .font(.caption2)
            Text(token.displayText)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(token.state.color.opacity(0.15), in: Capsule())
        .foregroundStyle(token.state.color)
    }
}

// MARK: - RadioPaletteHistory

enum RadioPaletteHistory {
    // MARK: Internal

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ command: String) {
        var history = load()
        history.removeAll { $0.lowercased() == command.lowercased() }
        history.insert(command, at: 0)
        if history.count > maxEntries {
            history = Array(history.prefix(maxEntries))
        }
        UserDefaults.standard.set(history, forKey: key)
    }

    // MARK: Private

    private static let key = "radioPaletteRecentCommands"
    private static let maxEntries = 20
}
