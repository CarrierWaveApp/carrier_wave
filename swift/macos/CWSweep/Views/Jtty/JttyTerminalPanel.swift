import AppKit
import SwiftUI

// MARK: - JttyTerminalPanel

/// The JTTY terminal: received text as it arrives (one line per message,
/// growing until EOM), what we sent, the F1–F8 contest macros, and a free-text
/// entry. Double-click a callsign in a received line to make it "his call".
struct JttyTerminalPanel: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            terminal
            Divider()
            operatorRow
            macroBar
            entryRow
        }
        .background(.background)
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    @Environment(JttyService.self) private var service
    @Environment(SelectionState.self) private var selectionState

    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    private var emptyText: String {
        switch service.sidecarStatus {
        case .running: "Listening on \(Int(service.toneFrequency)) Hz. Received text appears here as it decodes."
        case .notInstalled: "JTTY needs the jtty-sidecar helper. Install it here or in Settings → JTTY."
        default: "Enable the JTTY modem in Settings → JTTY, or click Start JTTY above."
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            statusChip
            if service.isRunning {
                levelMeter
            }
            Spacer()
            if service.isTransmitting {
                Label(service.pttEngaged ? "TX · PTT" : "TX", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.red)
                    .font(.caption.bold())
            }
            Button {
                service.resetDecoder()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reset the decoder")
            .disabled(!service.isRunning)
            Button {
                service.clearTerminal()
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear the terminal")
            .disabled(service.entries.isEmpty)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch service.sidecarStatus {
        case .running:
            Label("JTTY", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption.bold())
        case .notInstalled:
            Button("Install JTTY helper…") {
                Task { await service.installHelper() }
            }
            .buttonStyle(.link)
            .font(.caption)
        case .stopped:
            Button("Start JTTY") {
                Task { await service.setEnabled(true) }
            }
            .buttonStyle(.link)
            .font(.caption)
        case .starting,
             .installing:
            Label(service.sidecarStatus.label, systemImage: "ellipsis.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private var levelMeter: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ProgressView(value: Double(service.inputLevel))
                .frame(width: 70)
                .tint(service.inputLevel > 0.9 ? .red : .green)
        }
        .help(service.audioError ?? "Receive audio level")
    }

    private var terminal: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if service.entries.isEmpty {
                        Text(emptyText)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    ForEach(service.entries) { entry in
                        JttyTerminalRow(entry: entry, time: Self.timeFormatter.string(from: entry.date))
                            .id(entry.id)
                            .contextMenu { rowMenu(entry) }
                            .onTapGesture(count: 2) { pickCallsign(from: entry) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .onChange(of: service.entries.last?.id) { _, last in
                if let last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .onChange(of: service.entries.last?.text) { _, _ in
                if let last = service.entries.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var operatorRow: some View {
        @Bindable var service = service
        return HStack(spacing: 8) {
            TextField("His call", text: $service.hisCall)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
                .onSubmit { service.hisCall = service.hisCall.uppercased() }
            TextField("Queued", text: $service.queuedCall)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .help("Next-in-line station for F6 (TU NOW %Q)")
            if service.profile == .serial {
                Stepper("NR \(JttyMacroExpander.serialText(service.serial))", value: $service.serial, in: 1 ... 99_999)
                    .monospacedDigit()
            } else {
                TextField("Exchange", text: $service.exchange)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
            Spacer()
            Button("Log") {
                logHisCall()
            }
            .disabled(service.hisCall.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Send \(service.hisCall.uppercased()) JTTY to the log entry")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var macroBar: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< JttyMacroExpander.slotCount, id: \.self) { slot in
                Button {
                    service.sendMacro(slot: slot)
                } label: {
                    VStack(spacing: 1) {
                        Text("F\(slot + 1)")
                            .font(.caption2.bold())
                        Text(JttyMacroExpander.slotLabels[slot])
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(Self.functionKey(slot + 1), modifiers: [])
                .help(service.macroText(slot: slot))
            }
            Button {
                service.abortTransmit()
            } label: {
                VStack(spacing: 1) {
                    Text("Esc")
                        .font(.caption2.bold())
                    Text("Abort")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.escape, modifiers: [])
            .tint(.red)
            .disabled(!service.isTransmitting && service.pendingTransmissions == 0)
        }
        .disabled(!service.isRunning)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var entryRow: some View {
        HStack(spacing: 8) {
            TextField("Type text and press Return to send", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .focused($draftFocused)
                .onSubmit(sendDraft)
                .disabled(!service.isRunning)
            Button("Send", action: sendDraft)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!service.isRunning || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            if service.pendingTransmissions > 1 {
                Text("+\(service.pendingTransmissions - 1) queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func rowMenu(_ entry: JttyTerminalEntry) -> some View {
        let calls = JttyService.callsigns(in: entry.text)
        ForEach(calls, id: \.self) { call in
            Button("Use \(call) as his call") { service.hisCall = call }
            Button("Queue \(call)") { service.queuedCall = call }
        }
        if !calls.isEmpty {
            Divider()
        }
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
        }
    }

    private static func functionKey(_ number: Int) -> KeyEquivalent {
        // NSF1FunctionKey… are contiguous Unicode private-use code points.
        KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey + number - 1)!))
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        service.send(text)
        draftFocused = true
    }

    private func pickCallsign(from entry: JttyTerminalEntry) {
        guard entry.isReceived, let call = JttyService.callsigns(in: entry.text).first else {
            return
        }
        service.hisCall = call
    }

    private func logHisCall() {
        let call = service.hisCall.trimmingCharacters(in: .whitespaces).uppercased()
        guard !call.isEmpty else {
            return
        }
        selectionState.pendingSpotEntry = "\(call) JTTY"
        selectionState.requestEntryFocus = true
    }
}

// MARK: - JttyTerminalRow

struct JttyTerminalRow: View {
    // MARK: Internal

    let entry: JttyTerminalEntry
    let time: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 14)
            if let frequency = entry.frequency, entry.isReceived {
                Text("\(Int(frequency.rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            Text(entry.text + (entry.isComplete ? "" : " ▍"))
                .font(.body.monospaced())
                .foregroundStyle(color)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    // MARK: Private

    private var icon: String {
        switch entry.kind {
        case .received: "arrow.down"
        case .sent: "arrow.up"
        case .info: "info.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .received: entry.isComplete ? .primary : .secondary
        case .sent: .blue
        case .info: .secondary
        case .error: .red
        }
    }
}
