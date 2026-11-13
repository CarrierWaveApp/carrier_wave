import SwiftUI

/// Unified keyer control surface — routes through CW Bridge when available,
/// otherwise WinKeyer. Shows connection, speed, status, send box, F-keys.
struct KeyerControlView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            GroupBox("Connection") {
                connectionView
            }
            .padding(.horizontal)

            if isKeyerActive {
                GroupBox("Status") { statusView }
                    .padding(.horizontal)

                GroupBox("Speed") { speedControlView }
                    .padding(.horizontal)

                GroupBox("Send CW") { sendView }
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top)
    }

    // MARK: Private

    @Environment(RadioManager.self) private var radioManager
    @Environment(WinKeyerManager.self) private var winKeyer
    @Environment(SerialPortMonitor.self) private var portMonitor
    @State private var sendText = ""
    @State private var showPrefs = false

    /// True when at least one keyer (bridge or WinKeyer) is usable.
    private var isKeyerActive: Bool {
        radioManager.isBridgeKeyerAvailable || winKeyer.isConnected
    }

    /// Whether the active keyer is the CW Bridge.
    private var isBridgeActive: Bool {
        radioManager.isBridgeKeyerAvailable
    }

    /// Speed shown in the UI — bridge takes priority when active.
    private var displaySpeed: UInt8 {
        isBridgeActive ? radioManager.bridgeCWSpeed : winKeyer.speed
    }

    /// Whether the active keyer is currently transmitting.
    private var isSending: Bool {
        isBridgeActive ? radioManager.bridgeCWIsSending : winKeyer.isSending
    }

    private var header: some View {
        HStack {
            Text("Keyer Control")
                .font(.headline)
            if isBridgeActive {
                Text("CW Bridge")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
            } else if winKeyer.isConnected {
                Text("WinKeyer")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.yellow.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Spacer()
            if !isBridgeActive {
                Button("Refresh Ports") {
                    portMonitor.refreshPorts()
                }
            }
            Button {
                showPrefs.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("WinKeyer preferences")
            .popover(isPresented: $showPrefs, arrowEdge: .bottom) {
                WinKeyerPreferencesPopover()
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var connectionView: some View {
        if isBridgeActive {
            bridgeConnectedView
        } else if winKeyer.isConnected {
            winKeyerConnectedView
        } else {
            disconnectedView
        }
    }

    private var bridgeConnectedView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text("CW Bridge — keyer ready")
                    .fontWeight(.medium)
                if let fw = radioManager.bridgeFirmwareVersion {
                    Text("Firmware \(fw)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let radio = radioManager.bridgeDetectedRadio {
                    Text(radio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(4)
    }

    private var winKeyerConnectedView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text("Connected")
                    .fontWeight(.medium)
                if let port = winKeyer.connectedPortPath {
                    let portInfo = portMonitor.availablePorts.first(where: { $0.path == port })
                    Text(portInfo.map { portMonitor.displayName(for: $0) } ?? port)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if winKeyer.firmwareVersion > 0 {
                    Text("Firmware v\(winKeyer.firmwareVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Disconnect") {
                Task { await winKeyer.disconnect() }
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private var disconnectedView: some View {
        if portMonitor.availablePorts.isEmpty {
            Text("No serial ports detected. Connect a WinKeyer via USB or pair a CW Bridge in Radio settings.")
                .foregroundStyle(.secondary)
                .padding(4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(portMonitor.availablePorts) { port in
                    portRow(port)
                }
            }
            .padding(4)
        }

        if let error = winKeyer.lastError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(.callout)
            }
            .padding(4)
        }
    }

    private var statusView: some View {
        HStack(spacing: 16) {
            statusIndicator("BUSY", active: isSending, color: .green)
            if isBridgeActive {
                statusIndicator(
                    "DRAINING",
                    active: radioManager.bridgeCWFlags.contains(.draining),
                    color: .orange
                )
                Text("buf \(radioManager.bridgeCWBufferDepth)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                statusIndicator("BREAKIN", active: winKeyer.isBreakIn, color: .orange)
                statusIndicator("XOFF", active: winKeyer.isBufferFull, color: .red)
            }
            Spacer()
        }
        .padding(4)
    }

    private var speedControlView: some View {
        HStack {
            Text("\(displaySpeed) WPM")
                .font(.title2.monospacedDigit())
                .frame(width: 80, alignment: .leading)

            Stepper(
                "",
                value: Binding(
                    get: { Int(displaySpeed) },
                    set: { newValue in
                        Task {
                            await radioManager.setCWSpeed(newValue, fallback: winKeyer)
                        }
                    }
                ),
                in: 5 ... 99
            )
            .labelsHidden()

            Spacer()
        }
        .padding(4)
    }

    private var sendView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Type CW to send...", text: $sendText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(submitSend)

                Button("Send", action: submitSend)
                    .disabled(sendText.isEmpty)

                Button("Cancel", action: cancelSend)
                    .disabled(!isSending)
            }

            functionKeyButtons
        }
        .padding(4)
    }

    @ViewBuilder
    private var functionKeyButtons: some View {
        let messages = loadFKeyMessages()
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1 ... 6, id: \.self) { slot in
                    fKeyButton(slot: slot, message: messages[slot])
                }
            }
            HStack(spacing: 4) {
                ForEach(7 ... 12, id: \.self) { slot in
                    fKeyButton(slot: slot, message: messages[slot])
                }
            }
        }
    }

    private func portRow(_ port: SerialPortMonitor.SerialPortInfo) -> some View {
        HStack {
            Image(systemName: "cable.connector")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                PortNicknameEditor(port: port)
                Text(port.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Connect") {
                Task { await winKeyer.connect(port: port) }
            }
        }
    }

    private func statusIndicator(_ label: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? color : .gray.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(active ? .primary : .secondary)
        }
    }

    private func fKeyButton(slot: Int, message: String?) -> some View {
        Button {
            if let message, !message.isEmpty {
                Task { await radioManager.sendCW(message, fallback: winKeyer) }
            }
        } label: {
            Text("F\(slot)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
        }
        .disabled(message == nil || message?.isEmpty == true)
        .help(message ?? "F\(slot) — not configured")
    }

    private func submitSend() {
        guard !sendText.isEmpty else {
            return
        }
        let text = sendText
        sendText = ""
        Task { await radioManager.sendCW(text, fallback: winKeyer) }
    }

    private func cancelSend() {
        if isBridgeActive {
            Task { await radioManager.bridgeStopCW() }
        } else {
            Task { await winKeyer.cancelSending() }
        }
    }

    private func loadFKeyMessages() -> [Int: String] {
        var messages: [Int: String] = [:]
        for slot in 1 ... 12 {
            let key = "cwKeyer.f\(slot)"
            if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
                messages[slot] = stored
            }
        }
        return messages
    }
}
