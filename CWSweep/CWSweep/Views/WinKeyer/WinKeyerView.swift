import SwiftUI

/// WinKeyer connection, status, and CW sending interface.
struct WinKeyerView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("WinKeyer")
                    .font(.headline)
                Spacer()
                Button("Refresh Ports") {
                    portMonitor.refreshPorts()
                }
            }
            .padding(.horizontal)

            // Connection
            GroupBox("Connection") {
                if winKeyer.isConnected {
                    connectedView
                } else {
                    disconnectedView
                }
            }
            .padding(.horizontal)

            if winKeyer.isConnected {
                // Status indicators
                GroupBox("Status") {
                    statusView
                }
                .padding(.horizontal)

                // Speed control
                GroupBox("Speed") {
                    speedControlView
                }
                .padding(.horizontal)

                // Send CW
                GroupBox("Send CW") {
                    sendView
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top)
    }

    // MARK: Private

    @Environment(WinKeyerManager.self) private var winKeyer
    @Environment(SerialPortMonitor.self) private var portMonitor
    @State private var sendText = ""
    @State private var selectedPort: String?

    // MARK: - Connected View

    private var connectedView: some View {
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

    // MARK: - Disconnected View

    @ViewBuilder
    private var disconnectedView: some View {
        if portMonitor.availablePorts.isEmpty {
            Text("No serial ports detected. Connect a WinKeyer via USB.")
                .foregroundStyle(.secondary)
                .padding(4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(portMonitor.availablePorts) { port in
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

    // MARK: - Status View

    private var statusView: some View {
        HStack(spacing: 16) {
            statusIndicator("BUSY", active: winKeyer.isSending, color: .green)
            statusIndicator("BREAKIN", active: winKeyer.isBreakIn, color: .orange)
            statusIndicator("XOFF", active: winKeyer.isBufferFull, color: .red)
            Spacer()
        }
        .padding(4)
    }

    // MARK: - Speed Control

    private var speedControlView: some View {
        HStack {
            Text("\(winKeyer.speed) WPM")
                .font(.title2.monospacedDigit())
                .frame(width: 80, alignment: .leading)

            Stepper(
                "",
                value: Binding(
                    get: { Int(winKeyer.speed) },
                    set: { newValue in
                        let clamped = UInt8(clamping: newValue)
                        Task { await winKeyer.setSpeed(clamped) }
                    }
                ),
                in: 5 ... 99
            )
            .labelsHidden()

            Spacer()
        }
        .padding(4)
    }

    // MARK: - Send View

    private var sendView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Type CW to send...", text: $sendText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        guard !sendText.isEmpty else {
                            return
                        }
                        Task {
                            await winKeyer.sendText(sendText)
                            sendText = ""
                        }
                    }

                Button("Send") {
                    guard !sendText.isEmpty else {
                        return
                    }
                    Task {
                        await winKeyer.sendText(sendText)
                        sendText = ""
                    }
                }
                .disabled(sendText.isEmpty)

                Button("Cancel") {
                    Task { await winKeyer.cancelSending() }
                }
                .disabled(!winKeyer.isSending)
            }

            // F-key message buttons (2 rows of 6)
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
                Task { await winKeyer.sendText(message) }
            }
        } label: {
            Text("F\(slot)")
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
        }
        .disabled(message == nil || message?.isEmpty == true)
        .help(message ?? "F\(slot) — not configured")
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
