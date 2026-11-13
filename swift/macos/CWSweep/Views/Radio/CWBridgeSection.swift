import SwiftUI

// MARK: - CWBridgeSection

/// Radio Control section for discovering, pairing, and connecting to a CW
/// Bridge over BLE.
struct CWBridgeSection: View {
    // MARK: Internal

    let radioManager: RadioManager
    let discovery: BridgeDiscoveryService

    @Binding var connectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            deviceCard
            if radioManager.activeBridge != nil || radioManager.bridgeIsFramed {
                bridgeStatusCard
            }
            scanCard
        }
        .padding(.horizontal)
    }

    // MARK: Private

    @State private var showingForgetAlert = false

    private var isBridgeConnected: Bool {
        radioManager.activeBridgeSessionId != nil
    }

    private var detectedRadioLabel: String {
        if radioManager.bridgeDetecting {
            return "Detecting…"
        }
        return radioManager.bridgeDetectedRadio ?? "None"
    }

    private var deviceCard: some View {
        GroupBox("Paired CW Bridge") {
            if let uuid = discovery.savedDeviceUUID {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: isBridgeConnected
                        ? "antenna.radiowaves.left.and.right"
                        : "dot.radiowaves.left.and.right")
                        .foregroundStyle(isBridgeConnected ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(discovery.savedDeviceName ?? "CW Bridge")
                            .font(.body)
                        Text(uuid.uuidString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    connectButton(uuid: uuid)
                }
                .padding(8)
            } else {
                Text("No CW Bridge paired. Tap Scan to find a nearby bridge.")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }

    private var bridgeStatusCard: some View {
        GroupBox("Bridge Status") {
            VStack(alignment: .leading, spacing: 6) {
                statusRow(
                    label: "Firmware",
                    value: radioManager.bridgeFirmwareVersion ?? "—"
                )
                statusRow(
                    label: "Handshake",
                    value: radioManager.bridgeIsFramed ? "OK" : "Pending"
                )
                statusRow(
                    label: "USB device",
                    value: radioManager.bridgeUSBConnected ? "Connected" : "None"
                )
                statusRow(
                    label: "Detected radio",
                    value: detectedRadioLabel
                )
                if radioManager.bridgeHasCWKeyer {
                    statusRow(label: "CW keyer", value: "Available")
                }
                HStack {
                    Spacer()
                    Button("Re-detect Radio") {
                        Task { await radioManager.requestBridgeRedetect() }
                    }
                    .disabled(!radioManager.bridgeIsFramed)
                }
            }
            .padding(8)
        }
    }

    private var scanCard: some View {
        GroupBox("Discover") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if discovery.isScanning {
                        ProgressView().controlSize(.small)
                        Text("Scanning for BLE devices…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Pair a CW Bridge by scanning for Bluetooth devices.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    Spacer()
                    if discovery.isScanning {
                        Button("Stop") { discovery.stopScan() }
                    } else {
                        Button("Scan") { discovery.startScan() }
                    }
                }

                if !discovery.discoveredDevices.isEmpty {
                    List(discovery.discoveredDevices) { device in
                        DiscoveredDeviceRow(
                            device: device,
                            discovery: discovery
                        )
                    }
                    .frame(minHeight: 120, maxHeight: 180)
                }
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func connectButton(uuid: UUID) -> some View {
        if isBridgeConnected {
            Button("Disconnect") {
                Task { await radioManager.disconnectBridge() }
            }
        } else {
            HStack(spacing: 8) {
                Button("Forget") {
                    showingForgetAlert = true
                }
                .alert("Forget this CW Bridge?", isPresented: $showingForgetAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Forget", role: .destructive) {
                        discovery.forgetDevice()
                    }
                } message: {
                    Text("You'll need to scan and pair again to reconnect.")
                }
                Button("Connect") {
                    Task {
                        connectionError = nil
                        let profile = RadioProfile.fromBridge(
                            deviceUUID: uuid,
                            deviceName: discovery.savedDeviceName ?? "CW Bridge"
                        )
                        do {
                            _ = try await radioManager.connect(profile: profile)
                        } catch {
                            connectionError = "Bridge connect failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
        }
        .font(.callout)
    }
}

// MARK: - DiscoveredDeviceRow

private struct DiscoveredDeviceRow: View {
    let device: BLERadioTransport.DiscoveredDevice
    let discovery: BridgeDiscoveryService

    var body: some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(device.name)
                Text("RSSI \(device.rssi) dBm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Pair") {
                discovery.select(device)
            }
        }
    }
}
