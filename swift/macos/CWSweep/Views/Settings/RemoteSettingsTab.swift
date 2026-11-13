import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - RemoteSettingsTab

//
// Lets the user start/stop the remote LAN server, see the current pairing
// code for an iOS Field client to type, and revoke previously paired devices.

struct RemoteSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("Server") {
                serverStatusRow
                if case let .ready(port) = service.status {
                    LabeledContent("Listening on port") {
                        Text("\(port)")
                            .monospaced()
                    }
                }
                HStack {
                    Spacer()
                    Button(serverButtonLabel) {
                        toggleServer()
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }

            if isRunning {
                Section("Pairing") {
                    Text("On your iPhone, open Field, choose Remote, find this Mac, and enter the code below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Text(service.pairingCode ?? "------")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .tracking(8)
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        Button("New code") {
                            service.rotatePairingCode()
                        }
                    }
                }
            }

            Section("Nearby (no Wi-Fi)") {
                Toggle("Allow Field to connect over Bluetooth + peer Wi-Fi", isOn: multipeerBinding)
                Text(
                    "Uses MultipeerConnectivity (the same path AirDrop uses). Field still pairs with the 6-digit code."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Audio codec") {
                Toggle("Use Opus for remote audio", isOn: $opusEnabled)
                    .onChange(of: opusEnabled) { _, _ in
                        SharedEnvironment.shared.remoteOpPublishers.audioCodecPreferenceChanged()
                    }
                Text(opusFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Paired devices") {
                if service.pairedDevices.isEmpty {
                    Text("No devices yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.pairedDevices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(pairedSubtitle(for: device))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if service.activeDeviceIDs.contains(device.id) {
                                Label("Connected", systemImage: "circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                            Button("Revoke", role: .destructive) {
                                service.revokeDevice(device.id)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Private

    @Environment(RemoteOpService.self) private var service
    @AppStorage("remoteAudio.opusEnabled") private var opusEnabled = false

    private var multipeerBinding: Binding<Bool> {
        Binding(
            get: { service.multipeerEnabled },
            set: { service.multipeerEnabled = $0 }
        )
    }

    private var opusFooter: String {
        if !OpusCodec.isEncoderAvailable() {
            return "Opus encoder is unavailable on this Mac. Audio falls back to raw PCM."
        }
        if opusEnabled {
            return "Compresses RX audio ~10× before sending to Field. Latency adds ~20 ms each way."
        }
        return "Off: Field receives raw 16-bit PCM (~256 kbps per stream). Turn on to use Opus (~24 kbps)."
    }

    // MARK: - Private helpers

    private var isRunning: Bool {
        switch service.status {
        case .ready,
             .starting:
            true
        case .stopped,
             .failed:
            false
        }
    }

    private var serverButtonLabel: String {
        switch service.status {
        case .stopped,
             .failed: "Start server"
        case .starting: "Starting…"
        case .ready: "Stop server"
        }
    }

    @ViewBuilder
    private var serverStatusRow: some View {
        switch service.status {
        case .stopped:
            Label("Stopped", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        case .starting:
            Label("Starting…", systemImage: "ellipsis.circle")
        case .ready:
            Label("Ready — broadcasting on the local network", systemImage: "wifi")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private func pairedSubtitle(for device: PairedRemoteDevice) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        if let last = device.lastSeenAt {
            return "Last seen \(formatter.localizedString(for: last, relativeTo: Date()))"
        }
        return "Paired \(formatter.localizedString(for: device.pairedAt, relativeTo: Date()))"
    }

    private func toggleServer() {
        switch service.status {
        case .stopped,
             .failed:
            service.start()
            SharedEnvironment.shared.remoteOpPublishers.start()
        case .ready,
             .starting:
            SharedEnvironment.shared.remoteOpPublishers.stop()
            service.stop()
        }
    }
}
