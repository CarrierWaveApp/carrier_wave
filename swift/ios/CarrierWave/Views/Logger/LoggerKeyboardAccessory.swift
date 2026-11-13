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

            ForEach(Array(visibleRows.enumerated()), id: \.element) { index, kind in
                if index > 0 {
                    Divider()
                }
                rowView(for: kind)
            }
        }
        .background(Color(.secondarySystemBackground))
        .sheet(isPresented: $isEditingSlot) {
            if let slotID = editingSlotID {
                NavigationStack {
                    CWMessageEditorView(
                        slotID: slotID,
                        keyerService: RadioService.shared.cwKeyer
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { editingSlotID = nil; isEditingSlot = false }
                        }
                    }
                }
            }
        }
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
            prefixService.refreshIfNeeded()
        }
    }

    // MARK: Private

    // Row order + per-row enablement
    @AppStorage("keyboardRowOrder") private var rowOrderRaw = KeyboardRowKind.defaultOrderRaw
    @AppStorage("numberRowEnabled") private var numberRowEnabled = true

    // Number row configuration
    @AppStorage("keyboardRowShowNumbers") private var showNumbers = true
    @AppStorage("keyboardRowSymbols") private var symbolsString = "./"

    // Prefix row configuration (CAR-290)
    @AppStorage("prefixRowEnabled") private var prefixRowEnabled = true
    @AppStorage("prefixRowMode") private var prefixRowMode = "suggested"
    @AppStorage("prefixRowCustom") private var prefixRowCustom = ""

    // Command row configuration
    @AppStorage("commandRowEnabled") private var commandRowEnabled = false
    @AppStorage("commandRowCommands") private var commandsString = "rbn,solar,weather,spot,pota,p2p"

    @State private var enabledSymbols: [String] = []
    @State private var enabledCommands: [CommandRowItem] = []
    @State private var editingSlotID: Int?
    @State private var isEditingSlot: Bool = false
    @State private var prefixService = PrefixRowService.shared

    private var showKeyerRow: Bool {
        let service = RadioService.shared
        let hasCWKeyer = service.bridgeHasCWKeyer
        let usbConnected = service.bridgeUSBConnected
        let isCW = service.radioMode == "CW" || service.radioMode == "CW-R"
        let hasSlots = !service.cwKeyer.programmedSlots.isEmpty
        return hasCWKeyer && usbConnected && isCW && hasSlots
    }

    private var prefixChips: [String] {
        guard prefixRowEnabled else {
            return []
        }
        if prefixRowMode == "custom" {
            return prefixRowCustom.components(separatedBy: ",").filter { !$0.isEmpty }
        }
        return prefixService.suggested
    }

    private var visibleRows: [KeyboardRowKind] {
        KeyboardRowKind.order(from: rowOrderRaw).filter { kind in
            switch kind {
            case .numbers: numberRowEnabled && (showNumbers || !enabledSymbols.isEmpty)
            case .prefixes: !prefixChips.isEmpty
            case .keyer: showKeyerRow
            case .commands: commandRowEnabled && !enabledCommands.isEmpty
            }
        }
    }

    private var numberRow: some View {
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

    private var prefixRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(prefixChips, id: \.self) { prefix in
                    prefixButton(prefix)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
    }

    private var keyerRow: some View {
        CWKeyerRow(
            keyerService: RadioService.shared.cwKeyer,
            onPlay: { slot, ctx in playCWSlot(slot, context: ctx) },
            onStop: { stopCW() },
            onSendText: { text in sendCWText(text) },
            onEdit: { editingSlotID = $0; isEditingSlot = true },
            onSpeedChange: { wpm in setCWSpeed(wpm) },
            context: { buildCWContext() }
        )
    }

    private var commandRow: some View {
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

    // MARK: - Rows

    @ViewBuilder
    private func rowView(for kind: KeyboardRowKind) -> some View {
        switch kind {
        case .numbers: numberRow
        case .prefixes: prefixRow
        case .keyer: keyerRow
        case .commands: commandRow
        }
    }

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

    private func prefixButton(_ prefix: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            text = CallsignPrefixer.apply(prefix, to: text, knownPrefixes: prefixChips)
        } label: {
            Text(prefix)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Prefix \(prefix)")
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

    private func playCWSlot(_ slot: Int, context: [String: String]) {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        guard RadioService.shared.bridgeUSBConnected else {
            RadioService.shared.addLog(.error, "CW play: no USB radio connected — refusing to key")
            return
        }
        RadioService.shared.cwSendingSlot = slot
        bridge.playCWSlotImmediate(UInt8(slot), context: context)
    }

    private func stopCW() {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        bridge.stopCWImmediate()
    }

    private func sendCWText(_ text: String) {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        guard RadioService.shared.bridgeUSBConnected else {
            RadioService.shared.addLog(.error, "CW send: no USB radio connected — refusing to key")
            return
        }
        let clamped = String(text.prefix(100))
        guard !clamped.isEmpty else {
            return
        }
        bridge.sendCWImmediate(clamped)
    }

    private func setCWSpeed(_ wpm: UInt8) {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        Task {
            try? await bridge.setCWSpeed(wpm: wpm)
        }
    }

    private func buildCWContext() -> [String: String] {
        RadioService.shared.cwKeyer.buildContext(
            from: CWKeyerContext(
                callsign: text,
                myCall: UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? "",
                myName: UserDefaults.standard.string(forKey: "loggerDefaultName") ?? "",
                serial: RadioService.shared.cwSerialNumber,
                rstSent: "599",
                name: "",
                exchange: UserDefaults.standard.string(forKey: "contestExchange") ?? ""
            )
        )
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
