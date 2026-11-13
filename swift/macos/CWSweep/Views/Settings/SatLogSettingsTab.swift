import AppKit
import SwiftUI

// MARK: - SatLogSettingsTab

/// Settings for the CSN Technologies S.A.T. satellite-tracker log listener:
/// enable toggle, UDP/TCP transport, port, this Mac's LAN address (what to
/// type into the S.A.T.'s "QSO LOG IP"), listener status, and the most recent
/// records received.
struct SatLogSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            listenerSection
            configureSection
            recentSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            portText = String(service.port)
            addresses = LANAddress.ipv4Entries()
        }
    }

    // MARK: Private

    @Environment(SatLogListenerService.self) private var service

    @State private var portText = ""
    @State private var addresses: [LANAddress.Entry] = []
    @FocusState private var portFocused: Bool

    private var listenerSection: some View {
        Section("Listener") {
            Toggle("Accept QSOs pushed by a S.A.T. tracker", isOn: Binding(
                get: { service.isEnabled },
                set: { service.isEnabled = $0 }
            ))
            Picker("Transport", selection: Binding(
                get: { service.transport },
                set: { service.transport = $0 }
            )) {
                ForEach(SatLogTransport.allCases) { transport in
                    Text(transport.displayName).tag(transport)
                }
            }
            .pickerStyle(.segmented)
            LabeledContent("Port") {
                TextField("Port", text: $portText)
                    .labelsHidden()
                    .monospaced()
                    .frame(width: 90)
                    .focused($portFocused)
                    .onSubmit { commitPort() }
                    .onChange(of: portFocused) { _, focused in
                        if !focused {
                            commitPort()
                        }
                    }
            }
            statusRow
            if let error = service.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var configureSection: some View {
        Section("Configure your S.A.T.") {
            if addresses.isEmpty {
                Text("No LAN IPv4 address found — connect this Mac to Wi-Fi or Ethernet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(addresses) { entry in
                    HStack {
                        Text(entry.address)
                            .monospaced()
                        Text(entry.interface)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyToClipboard(entry.address)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy address")
                    }
                }
            }
            Text(
                "In the S.A.T. web interface open Location. Set QSO LOG TYPE to a logger that "
                    + "receives plain ADIF over the transport chosen above (for UDP: N1MM or Log4OM; "
                    + "for TCP: ACLog or DXKeeper) and set QSO LOG IP to this Mac's address with port "
                    + "\(service.port). Each QSO the S.A.T. logs then lands in Sweep tagged S.A.T., "
                    + "with SAT_NAME and PROP_MODE preserved."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var recentSection: some View {
        Section {
            if service.recentRecords.isEmpty {
                Text(service.isRunning ? "Waiting for the first record…" : "Nothing received yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.recentRecords) { record in
                    SatLogRecentRecordRow(record: record)
                }
            }
        } header: {
            HStack {
                Text("Recent records")
                Spacer()
                Text("\(service.receivedCount) received")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if service.isRunning {
            Label(
                "Listening on \(service.transport.displayName) port \(service.port)",
                systemImage: "antenna.radiowaves.left.and.right"
            )
            .foregroundStyle(.green)
        } else if service.isEnabled {
            Label("Starting…", systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
        } else {
            Label("Off", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func commitPort() {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let value = UInt16(trimmed), value > 0 else {
            portText = String(service.port)
            return
        }
        if value != service.port {
            service.port = value
        }
        portText = String(value)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - SatLogRecentRecordRow

private struct SatLogRecentRecordRow: View {
    // MARK: Internal

    let record: SatLogReceivedRecord

    var body: some View {
        HStack(spacing: 10) {
            Text(record.receivedAt, format: .dateTime.hour().minute().second())
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(record.callsign)
                .fontWeight(.semibold)
                .monospaced()
            Text(record.summary)
                .foregroundStyle(.secondary)
            Spacer()
            outcomeLabel
        }
        .font(.callout)
        .help("From \(record.sender)")
    }

    // MARK: Private

    @ViewBuilder
    private var outcomeLabel: some View {
        switch record.outcome {
        case .logged:
            Label("Logged", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .duplicate:
            Label("Duplicate", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case let .skipped(reason):
            Label(reason, systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}
