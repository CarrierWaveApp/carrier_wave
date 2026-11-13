import AppKit
import SwiftUI

// MARK: - CommandLogSection

/// Live TX/RX command log shown at the bottom of Radio Control.
struct CommandLogSection: View {
    // MARK: Internal

    let commandLog: RadioCommandLog

    var body: some View {
        GroupBox("Command Log") {
            if commandLog.entries.isEmpty {
                Text("No commands yet. Connect a radio to see TX/RX traffic.")
                    .foregroundStyle(.secondary)
                    .padding(4)
            } else {
                logScroll
            }

            HStack {
                Spacer()
                Text("\(commandLog.entries.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Copy") {
                    copyCommandLog()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                Button("Clear") {
                    commandLog.clear()
                }
                .buttonStyle(.plain)
                .font(.caption2)
            }
        }
        .frame(maxHeight: 200)
        .padding(.horizontal)
    }

    // MARK: Private

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(commandLog.entries) { entry in
                        CommandLogEntryRow(entry: entry)
                    }
                }
                .padding(4)
            }
            .onChange(of: commandLog.entries.last?.id) { _, newId in
                if let newId {
                    proxy.scrollTo(newId, anchor: .bottom)
                }
            }
        }
    }

    private func copyCommandLog() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.S"
        let lines: [String] = commandLog.entries.map { entry in
            let ts = formatter.string(from: entry.timestamp)
            let dir = switch entry.direction {
            case .tx: "TX"
            case .rx: "RX"
            case .status: "--"
            }
            return "\(ts) \(dir)\t\(entry.text)"
        }
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - CommandLogEntryRow

private struct CommandLogEntryRow: View {
    // MARK: Internal

    let entry: RadioCommandEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(
                entry.timestamp,
                format: .dateTime.hour().minute().second().secondFraction(.fractional(1))
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Text(directionLabel)
                .font(.caption.bold())
                .foregroundStyle(directionColor)
                .frame(width: 20, alignment: .leading)

            Text(entry.text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .id(entry.id)
    }

    // MARK: Private

    private var directionLabel: String {
        switch entry.direction {
        case .tx: "TX"
        case .rx: "RX"
        case .status: "--"
        }
    }

    private var directionColor: Color {
        switch entry.direction {
        case .tx: .blue
        case .rx: .green
        case .status: .secondary
        }
    }
}
