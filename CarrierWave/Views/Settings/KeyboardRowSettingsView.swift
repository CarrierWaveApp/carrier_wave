// Keyboard Row Settings View
//
// Configures which numbers and symbols appear in the keyboard
// accessory row above the keyboard in the logger.

import SwiftUI

// MARK: - Notification Name

extension Notification.Name {
    static let keyboardRowConfigurationChanged = Notification.Name(
        "keyboardRowConfigurationChanged"
    )
}

// MARK: - KeyboardRowSettingsView

struct KeyboardRowSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            previewSection
            numbersSection
            enabledSymbolsSection
            availableSymbolsSection
            resetSection
        }
        .navigationTitle("Keyboard Row")
        .environment(\.editMode, .constant(.active))
        .onAppear {
            refreshSymbols()
        }
    }

    // MARK: Private

    private static let allSymbols = [".", "/", "-", "+", ",", ";", ":"]

    @AppStorage("keyboardRowShowNumbers") private var showNumbers = true
    @AppStorage("keyboardRowSymbols") private var symbolsString = "/"

    @State private var enabledSymbols: [String] = []
    @State private var availableSymbols: [String] = []

    private var previewSection: some View {
        Section {
            KeyboardRowPreview(
                showNumbers: showNumbers,
                symbols: enabledSymbols
            )
        } header: {
            Text("Preview")
        }
    }

    private var numbersSection: some View {
        Section {
            Toggle("Numbers (0-9)", isOn: $showNumbers)
                .onChange(of: showNumbers) { _, _ in
                    notifyChange()
                }
        } footer: {
            Text("Numbers appear before symbols in the keyboard row.")
        }
    }

    private var enabledSymbolsSection: some View {
        Section {
            if enabledSymbols.isEmpty {
                Text("No symbols enabled")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(enabledSymbols, id: \.self) { symbol in
                    symbolRow(symbol, enabled: true)
                }
                .onMove(perform: moveEnabledSymbol)
            }
        } header: {
            Text("Enabled Symbols")
        } footer: {
            Text("Drag to reorder. Tap to disable.")
        }
    }

    private var availableSymbolsSection: some View {
        Section {
            if availableSymbols.isEmpty {
                Text("All symbols enabled")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableSymbols, id: \.self) { symbol in
                    symbolRow(symbol, enabled: false)
                }
            }
        } header: {
            Text("Available Symbols")
        } footer: {
            Text("Tap to enable.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                showNumbers = true
                symbolsString = "./"
                refreshSymbols()
            }
        }
    }

    private func symbolRow(_ symbol: String, enabled: Bool) -> some View {
        Button {
            toggleSymbol(symbol, enabled: enabled)
        } label: {
            HStack {
                Text(symbol)
                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(symbolName(symbol))
                    .foregroundStyle(enabled ? .primary : .secondary)

                Spacer()

                Image(systemName: enabled ? "minus.circle" : "plus.circle")
                    .foregroundStyle(enabled ? .red : .green)
            }
        }
        .buttonStyle(.plain)
    }

    private func symbolName(_ symbol: String) -> String {
        switch symbol {
        case ".": "Period"
        case "/": "Slash"
        case "-": "Dash"
        case "+": "Plus"
        case ",": "Comma"
        case ";": "Semicolon"
        case ":": "Colon"
        default: symbol
        }
    }

    private func refreshSymbols() {
        let current = symbolsString.isEmpty ? [] : symbolsString.components(separatedBy: ",")
        enabledSymbols = current.filter { Self.allSymbols.contains($0) }
        availableSymbols = Self.allSymbols.filter { !enabledSymbols.contains($0) }
    }

    private func saveSymbols() {
        symbolsString = enabledSymbols.joined(separator: ",")
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .keyboardRowConfigurationChanged, object: nil)
    }

    private func toggleSymbol(_ symbol: String, enabled: Bool) {
        if enabled {
            enabledSymbols.removeAll { $0 == symbol }
            availableSymbols.append(symbol)
            // Sort available symbols to maintain consistent order
            availableSymbols.sort {
                Self.allSymbols.firstIndex(of: $0)! < Self.allSymbols.firstIndex(of: $1)!
            }
        } else {
            availableSymbols.removeAll { $0 == symbol }
            enabledSymbols.append(symbol)
        }
        saveSymbols()
    }

    private func moveEnabledSymbol(from source: IndexSet, to destination: Int) {
        enabledSymbols.move(fromOffsets: source, toOffset: destination)
        saveSymbols()
    }
}

// MARK: - KeyboardRowPreview

struct KeyboardRowPreview: View {
    // MARK: Internal

    let showNumbers: Bool
    let symbols: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if showNumbers {
                    ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], id: \.self) { num in
                        previewButton(num)
                    }
                }
                ForEach(symbols, id: \.self) { symbol in
                    previewButton(symbol)
                }
                // Dismiss button placeholder
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Private

    private func previewButton(_ char: String) -> some View {
        Text(char)
            .font(.system(size: 16, weight: .medium, design: .monospaced))
            .frame(width: 36, height: 36)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    NavigationStack {
        KeyboardRowSettingsView()
    }
}
