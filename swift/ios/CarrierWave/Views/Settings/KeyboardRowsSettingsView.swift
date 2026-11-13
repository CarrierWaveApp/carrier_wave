// Keyboard Rows Settings View
//
// Unified configuration hub for the logger's keyboard accessory rows
// (CAR-290): Numbers & Symbols, Prefixes, CW Keyer, Commands. Rows are
// toggled inline, dragged to reorder the stack, and drill into their
// own detail pages. A live preview of the stack is pinned at the
// bottom, mirroring where the rows actually sit above the keyboard.

import CarrierWaveData
import SwiftUI

// MARK: - KeyboardRowsSettingsView

struct KeyboardRowsSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            rowsSection
            resetSection
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Keyboard Rows")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushedRow) { kind in
            detailView(for: kind)
        }
        .safeAreaInset(edge: .bottom) {
            KeyboardRowsStackPreview(highlighted: nil)
        }
        .onAppear {
            PrefixRowService.shared.refreshIfNeeded()
        }
    }

    // MARK: Private

    @AppStorage("keyboardRowOrder") private var rowOrderRaw = KeyboardRowKind.defaultOrderRaw
    @AppStorage("numberRowEnabled") private var numberRowEnabled = true
    @AppStorage("keyboardRowShowNumbers") private var showNumbers = true
    @AppStorage("keyboardRowSymbols") private var symbolsString = "/"
    @AppStorage("prefixRowEnabled") private var prefixRowEnabled = true
    @AppStorage("prefixRowMode") private var prefixRowMode = "suggested"
    @AppStorage("prefixRowCustom") private var prefixRowCustom = ""
    @AppStorage("commandRowEnabled") private var commandRowEnabled = false
    @AppStorage("commandRowCommands") private var commandsString = "rbn,solar,weather,spot,hunt,p2p"

    @State private var pushedRow: KeyboardRowKind?

    private var rowOrder: [KeyboardRowKind] {
        KeyboardRowKind.order(from: rowOrderRaw)
    }

    private var rowsSection: some View {
        Section {
            ForEach(rowOrder) { kind in
                rowEntry(kind)
            }
            .onMove(perform: moveRow)
        } header: {
            Text("Rows")
        } footer: {
            Text(
                """
                Drag to reorder — rows stack above the keyboard in this order. \
                The CW Keyer row appears automatically when a CW bridge is \
                connected, the radio is in CW mode, and at least one message \
                is programmed; its position here still applies.
                """
            )
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                rowOrderRaw = KeyboardRowKind.defaultOrderRaw
                numberRowEnabled = true
                showNumbers = true
                symbolsString = "./"
                prefixRowEnabled = true
                prefixRowMode = "suggested"
                prefixRowCustom = ""
                commandRowEnabled = false
                notifyChange()
            }
        }
    }

    private func rowEntry(_ kind: KeyboardRowKind) -> some View {
        Button {
            pushedRow = kind
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(kind.displayName)
                            .foregroundStyle(.primary)
                        if kind == .prefixes {
                            Text("NEW")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue)
                                .foregroundStyle(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(summary(for: kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if kind == .keyer {
                    Text("Automatic")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Show \(kind.displayName) row", isOn: enabledBinding(for: kind))
                        .labelsHidden()
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func detailView(for kind: KeyboardRowKind) -> some View {
        switch kind {
        case .numbers:
            KeyboardRowSettingsView()
        case .prefixes:
            PrefixRowSettingsView()
        case .keyer:
            KeyerRowSettingsView()
        case .commands:
            CommandRowSettingsView()
        }
    }

    private func enabledBinding(for kind: KeyboardRowKind) -> Binding<Bool> {
        switch kind {
        case .numbers:
            Binding(
                get: { numberRowEnabled },
                set: { numberRowEnabled = $0; notifyChange() }
            )
        case .prefixes:
            Binding(
                get: { prefixRowEnabled },
                set: { prefixRowEnabled = $0; notifyChange() }
            )
        case .commands:
            Binding(
                get: { commandRowEnabled },
                set: { commandRowEnabled = $0; notifyChange() }
            )
        case .keyer:
            .constant(true)
        }
    }

    private func summary(for kind: KeyboardRowKind) -> String {
        switch kind {
        case .numbers:
            var parts: [String] = []
            if showNumbers {
                parts.append("1–9 0")
            }
            let symbols = symbolsString.components(separatedBy: ",").filter { !$0.isEmpty }
            if !symbols.isEmpty {
                parts.append(symbols.joined(separator: " "))
            }
            return parts.isEmpty ? "Nothing enabled" : parts.joined(separator: " ")

        case .prefixes:
            let chips: [String]
            let label: String
            if prefixRowMode == "custom" {
                chips = prefixRowCustom.components(separatedBy: ",").filter { !$0.isEmpty }
                label = "Custom"
            } else {
                chips = PrefixRowService.shared.suggested
                label = "Near \(DeviceLocationHint.lastKnownGrid ?? "you")"
            }
            guard !chips.isEmpty else {
                return "\(label) · none yet"
            }
            let head = chips.prefix(3).joined(separator: " ")
            return "\(label) · \(head)\(chips.count > 3 ? " …" : "")"

        case .keyer:
            return "CW bridge · programmed messages"

        case .commands:
            let commands = commandsString.components(separatedBy: ",").filter { !$0.isEmpty }
            return commands.isEmpty ? "No commands enabled" : "\(commands.count) commands"
        }
    }

    private func moveRow(from source: IndexSet, to destination: Int) {
        var order = rowOrder
        order.move(fromOffsets: source, toOffset: destination)
        rowOrderRaw = order.map(\.rawValue).joined(separator: ",")
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .keyboardRowConfigurationChanged, object: nil)
    }
}

// MARK: - KeyboardRowsStackPreview

/// Live preview of the accessory stack, pinned at the bottom of the
/// Keyboard Rows screens the way the real rows pin above the keyboard.
struct KeyboardRowsStackPreview: View {
    // MARK: Internal

    /// Row outlined as "being edited", if any.
    let highlighted: KeyboardRowKind?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(visibleRows) { kind in
                previewRow(kind)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay {
                        if kind == highlighted {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.blue, lineWidth: 2)
                        }
                    }
                Divider()
            }
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .accessibilityHidden(true)
                Text("Keyboard")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Private

    @AppStorage("keyboardRowOrder") private var rowOrderRaw = KeyboardRowKind.defaultOrderRaw
    @AppStorage("numberRowEnabled") private var numberRowEnabled = true
    @AppStorage("keyboardRowShowNumbers") private var showNumbers = true
    @AppStorage("keyboardRowSymbols") private var symbolsString = "/"
    @AppStorage("prefixRowEnabled") private var prefixRowEnabled = true
    @AppStorage("prefixRowMode") private var prefixRowMode = "suggested"
    @AppStorage("prefixRowCustom") private var prefixRowCustom = ""
    @AppStorage("commandRowEnabled") private var commandRowEnabled = false
    @AppStorage("commandRowCommands") private var commandsString = "rbn,solar,weather,spot,hunt,p2p"

    @State private var prefixService = PrefixRowService.shared

    private var visibleRows: [KeyboardRowKind] {
        KeyboardRowKind.order(from: rowOrderRaw).filter { kind in
            switch kind {
            case .numbers: numberRowEnabled
            case .prefixes: prefixRowEnabled && !prefixChips.isEmpty
            case .keyer: true
            case .commands: commandRowEnabled
            }
        }
    }

    private var prefixChips: [String] {
        if prefixRowMode == "custom" {
            return prefixRowCustom.components(separatedBy: ",").filter { !$0.isEmpty }
        }
        return prefixService.suggested
    }

    private var numberKeys: [String] {
        var keys: [String] = []
        if showNumbers {
            keys += (1 ... 9).map(String.init) + ["0"]
        }
        keys += symbolsString.components(separatedBy: ",").filter { !$0.isEmpty }
        return keys
    }

    private var commandLabels: [String] {
        commandsString.components(separatedBy: ",")
            .compactMap { CommandRowItem(rawValue: $0 == "pota" ? "hunt" : $0)?.label }
    }

    @ViewBuilder
    private func previewRow(_ kind: KeyboardRowKind) -> some View {
        switch kind {
        case .numbers:
            previewKeys(numberKeys)
        case .prefixes:
            previewKeys(prefixChips)
        case .keyer:
            previewKeys(["CQ", "EXCH", "TU", "73", "STOP"])
        case .commands:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(commandLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func previewKeys(_ keys: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(height: 26)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        KeyboardRowsSettingsView()
    }
}
