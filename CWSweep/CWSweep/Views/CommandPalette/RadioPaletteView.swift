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

    @State var searchText = ""
    @State var recentCommands: [String] = RadioPaletteHistory.load()
    @State var historyIndex: Int?
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Environment(RadioManager.self) var radioManager
    @Environment(ClusterManager.self) var clusterManager
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
                helpRow("PARK K-0001", "Set POTA park")
            }
        }
    }

    // MARK: - Parse Result

    private var parseResultView: some View {
        let (command, tokens) = RadioCommandParser.parse(searchText)

        return VStack(alignment: .leading, spacing: 12) {
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
        VStack(spacing: 8) {
            Text("Could not parse command")
                .foregroundStyle(.secondary)
            Text("Try: frequency [mode] [UP/DOWN offset]")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
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

    private func tokenPills(_ tokens: [ParsedToken]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(tokens) { token in
                tokenPill(token)
            }
        }
    }

    private func tokenPill(_ token: ParsedToken) -> some View {
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

    private func commandSummary(_ command: RadioCommand) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let named = command.namedCommand {
                namedCommandSummary(named)
            }
            if let freq = command.frequencyMHz {
                summaryRow("Frequency", FrequencyFormatter.formatWithUnit(freq))
            }
            if let mode = command.mode {
                let resolved = RadioCommandParser.resolveMode(mode, frequencyMHz: command.frequencyMHz)
                if resolved != mode {
                    summaryRow("Mode", "\(mode) (\(resolved))")
                } else {
                    summaryRow("Mode", mode)
                }
            }
            if let split = command.splitDirective {
                summaryRow("Split", split.description)
            }
        }
    }

    private func namedCommandSummary(_ cmd: NamedCommand) -> some View {
        Group {
            switch cmd {
            case let .lookup(callsign):
                summaryRow("Action", "Look up \(callsign)")
            case let .spot(callsign, freq):
                summaryRow("Action", "Spot \(callsign)")
                if let freqKHz = freq {
                    summaryRow("Frequency", FrequencyFormatter.formatWithUnit(freqKHz / 1_000))
                } else {
                    summaryRow("Frequency", "Current radio frequency")
                }
                if !clusterManager.isConnected {
                    summaryRow("Warning", "Cluster not connected")
                }
            case let .setPark(ref):
                summaryRow("Action", "Set POTA park to \(ref)")
            case let .setSummit(ref):
                summaryRow("Action", "Set SOTA summit to \(ref)")
            case let .setPower(watts):
                summaryRow("Action", "Set power to \(watts)W")
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
        }
    }
}

// MARK: - RadioPaletteView + Actions

extension RadioPaletteView {
    func executeCommand() {
        let (command, _) = RadioCommandParser.parse(searchText)
        guard !command.isEmpty else {
            dismiss()
            return
        }

        let input = searchText.trimmingCharacters(in: .whitespaces)
        if !input.isEmpty {
            RadioPaletteHistory.add(input)
        }

        Task {
            await applyCommand(command)
        }
        dismiss()
    }

    func applyCommand(_ command: RadioCommand) async {
        if let named = command.namedCommand {
            await applyNamedCommand(named)
            return
        }
        if let freq = command.frequencyMHz {
            try? await radioManager.tuneToFrequency(freq)
        }
        if let mode = command.mode {
            let resolved = RadioCommandParser.resolveMode(mode, frequencyMHz: command.frequencyMHz)
            try? await radioManager.setMode(resolved)
        }
        if let split = command.splitDirective {
            await applySplit(split)
        }
    }

    func applyNamedCommand(_ cmd: NamedCommand) async {
        switch cmd {
        case .lookup:
            // Lookup is informational — future: open inspector with callsign info
            break

        case let .spot(callsign, frequencyKHz):
            guard clusterManager.isConnected else {
                return
            }
            let freq = frequencyKHz ?? (radioManager.frequency * 1_000)
            let spotCmd = "DX \(String(format: "%.1f", freq)) \(callsign)"
            clusterManager.sendCommand(spotCmd)

        case let .setPark(reference):
            updateActiveSession { $0.parkReference = reference }

        case let .setSummit(reference):
            updateActiveSession { $0.sotaReference = reference }

        case .setPower:
            // Power control requires CAT protocol extension — not yet implemented
            break
        }
    }

    func updateActiveSession(_ update: (LoggingSession) -> Void) {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active"
            },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let session = try? modelContext.fetch(descriptor).first else {
            return
        }
        update(session)
        try? modelContext.save()
    }

    func applySplit(_ split: SplitDirective) async {
        switch split {
        case let .up(kHz):
            try? await radioManager.setXIT(true)
            try? await radioManager.setXITOffset(Int(kHz * 1_000))
        case let .down(kHz):
            try? await radioManager.setXIT(true)
            try? await radioManager.setXITOffset(Int(-kHz * 1_000))
        case let .explicitFrequency(kHz):
            try? await radioManager.setXIT(true)
            let currentKHz = radioManager.frequency * 1_000
            let offsetHz = Int((kHz - currentKHz) * 1_000)
            try? await radioManager.setXITOffset(offsetHz)
        case .off:
            try? await radioManager.clearRITXIT()
        }
    }

    func navigateHistory(direction: HistoryDirection) {
        guard !recentCommands.isEmpty else {
            return
        }

        switch direction {
        case .up:
            if let current = historyIndex {
                historyIndex = min(current + 1, recentCommands.count - 1)
            } else {
                historyIndex = 0
            }
        case .down:
            if let current = historyIndex {
                if current <= 0 {
                    historyIndex = nil
                    searchText = ""
                    return
                }
                historyIndex = current - 1
            }
        }

        if let idx = historyIndex, idx < recentCommands.count {
            searchText = recentCommands[idx]
        }
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
