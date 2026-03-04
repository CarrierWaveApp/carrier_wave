// Logger Keyboard Accessory
//
// Provides a number row and optional command buttons above the keyboard.

import CarrierWaveData
import SwiftUI

// MARK: - LoggerKeyboardAccessory

struct LoggerKeyboardAccessory: View {
    // MARK: Internal

    @Binding var text: String

    let onCommand: (LoggerCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Number row
            if showNumbers || !enabledSymbols.isEmpty {
                HStack(spacing: 4) {
                    if showNumbers {
                        ForEach(1 ... 9, id: \.self) { num in
                            numberButton(String(num))
                        }
                        numberButton("0")
                    }
                    ForEach(enabledSymbols, id: \.self) { symbol in
                        numberButton(symbol)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }

            // Command row (optional)
            if commandRowEnabled, !enabledCommands.isEmpty {
                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(enabledCommands, id: \.self) { item in
                            commandButton(item)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 6)
            }
        }
        .background(Color(.secondarySystemBackground))
        .onReceive(
            NotificationCenter.default.publisher(for: .keyboardRowConfigurationChanged)
        ) { _ in
            refreshNumberRowConfig()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .commandRowConfigurationChanged)
        ) { _ in
            refreshCommandRowConfig()
        }
        .onAppear {
            refreshNumberRowConfig()
            refreshCommandRowConfig()
        }
    }

    // MARK: Private

    // Number row configuration
    @AppStorage("keyboardRowShowNumbers") private var showNumbers = true
    @AppStorage("keyboardRowSymbols") private var symbolsString = "./"

    // Command row configuration
    @AppStorage("commandRowEnabled") private var commandRowEnabled = false
    @AppStorage("commandRowCommands") private var commandsString = "rbn,solar,weather,spot,pota,p2p"

    @State private var enabledSymbols: [String] = []
    @State private var enabledCommands: [CommandRowItem] = []

    // MARK: - Button Builders

    private func numberButton(_ char: String) -> some View {
        Button {
            text.append(char)
        } label: {
            Text(char)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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

    private func refreshNumberRowConfig() {
        enabledSymbols = symbolsString.isEmpty ? [] : symbolsString.components(separatedBy: ",")
    }

    private func refreshCommandRowConfig() {
        let keys = commandsString.isEmpty ? [] : commandsString.components(separatedBy: ",")
        enabledCommands = keys.compactMap { CommandRowItem(rawValue: $0) }
    }
}

// MARK: - KeyboardAccessoryModifier

struct KeyboardAccessoryModifier: ViewModifier {
    @Binding var text: String

    let onCommand: (LoggerCommand) -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    // Number row for frequency entry
                    Button("1") { text.append("1") }
                    Button("2") { text.append("2") }
                    Button("3") { text.append("3") }
                    Button("4") { text.append("4") }
                    Button("5") { text.append("5") }
                    Button("6") { text.append("6") }
                    Button("7") { text.append("7") }
                    Button("8") { text.append("8") }
                    Button("9") { text.append("9") }
                    Button("0") { text.append("0") }
                    Button(".") { text.append(".") }
                }
            }
    }
}

extension View {
    func loggerKeyboardAccessory(
        text: Binding<String>,
        onCommand: @escaping (LoggerCommand) -> Void
    ) -> some View {
        modifier(KeyboardAccessoryModifier(text: text, onCommand: onCommand))
    }
}

#Preview {
    VStack {
        Spacer()
        LoggerKeyboardAccessory(text: .constant("")) { _ in }
    }
}
