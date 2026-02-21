// iPad Command Strip
//
// Persistent command row displayed at the bottom of the logger pane on iPad.
// Shown only when the keyboard is NOT visible — the keyboard accessory
// provides its own command row while typing.

import SwiftUI

// MARK: - IPadCommandStrip

struct IPadCommandStrip: View {
    // MARK: Internal

    let onCommand: (LoggerCommand) -> Void

    var body: some View {
        Group {
            if !isKeyboardVisible {
                stripContent
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification
            )
        ) { _ in
            isKeyboardVisible = true
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )
        ) { _ in
            isKeyboardVisible = false
        }
    }

    // MARK: Private

    @AppStorage("commandRowEnabled") private var commandRowEnabled = false
    @AppStorage("commandRowCommands") private var commandsString =
        "rbn,solar,weather,spot,pota,p2p"

    @State private var configuredCommands: [CommandRowItem] = []
    @State private var isKeyboardVisible = false

    /// Show configured commands if enabled, otherwise fall back to all commands.
    private var displayCommands: [CommandRowItem] {
        if commandRowEnabled, !configuredCommands.isEmpty {
            return configuredCommands
        }
        return CommandRowItem.allCases
    }

    private var stripContent: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(displayCommands, id: \.self) { item in
                        commandButton(item)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
        .onReceive(
            NotificationCenter.default.publisher(for: .commandRowConfigurationChanged)
        ) { _ in
            refreshConfig()
        }
        .onAppear {
            refreshConfig()
        }
    }

    private func commandButton(_ item: CommandRowItem) -> some View {
        Button {
            onCommand(item.command)
        } label: {
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
        .buttonStyle(.plain)
    }

    private func refreshConfig() {
        let keys = commandsString.isEmpty
            ? []
            : commandsString.components(separatedBy: ",")
        configuredCommands = keys.compactMap { CommandRowItem(rawValue: $0) }
    }
}
