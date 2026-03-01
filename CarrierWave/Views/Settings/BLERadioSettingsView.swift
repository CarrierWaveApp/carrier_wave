import SwiftUI

// MARK: - BLERadioSettingsView

/// Settings screen for BLE radio CAT control configuration.
struct BLERadioSettingsView: View {
    // MARK: Internal

    @State var bleRadioService: BLERadioService

    var body: some View {
        List {
            savedDeviceSection
            scanSection
            advancedSection
        }
        .navigationTitle("BLE Radio")
        .onAppear {
            let addr = UserDefaults.standard.integer(forKey: "bleRadio.rigAddress")
            let address = addr > 0 ? UInt8(addr) : 0xA4
            rigAddressText = String(format: "%02X", address)
        }
        .onDisappear {
            bleRadioService.stopScan()
        }
    }

    // MARK: Private

    @State private var rigAddressText: String = ""

    // MARK: - Helpers

    private var connectionStatusText: String {
        switch bleRadioService.connectionStatus {
        case .disconnected: "Disconnected"
        case .scanning: "Scanning..."
        case let .connecting(phase): "Connecting: \(phase)"
        case .connected: "Connected"
        case let .error(msg): msg
        }
    }

    private var connectionStatusColor: Color {
        switch bleRadioService.connectionStatus {
        case .connected: .green
        case .error: .red
        default: .secondary
        }
    }

    // MARK: - Saved Device

    @ViewBuilder
    private var savedDeviceSection: some View {
        if let name = bleRadioService.savedDeviceName {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                        Text(connectionStatusText)
                            .font(.caption)
                            .foregroundStyle(connectionStatusColor)
                    }
                    Spacer()
                    connectionStatusDot
                }

                if !bleRadioService.isConnected {
                    Button("Connect") {
                        bleRadioService.connectToSavedDevice()
                    }
                } else {
                    Button("Disconnect") {
                        bleRadioService.disconnect()
                    }
                }

                Button("Forget Device", role: .destructive) {
                    bleRadioService.forgetDevice()
                }
            } header: {
                Text("Saved Device")
            }
        }
    }

    // MARK: - Scan

    private var scanSection: some View {
        Section {
            Button {
                if bleRadioService.isScanning {
                    bleRadioService.stopScan()
                } else {
                    bleRadioService.startScan()
                }
            } label: {
                HStack {
                    Text(bleRadioService.isScanning ? "Stop Scanning" : "Scan for Devices")
                    if bleRadioService.isScanning {
                        Spacer()
                        ProgressView()
                    }
                }
            }

            ForEach(bleRadioService.discoveredDevices) { device in
                Button {
                    bleRadioService.selectDevice(device)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(device.id.uuidString.prefix(8) + "...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        rssiIndicator(device.rssi)
                    }
                }
            }
        } header: {
            Text("Devices")
        } footer: {
            Text("Scan for BLE CAT proxy devices (Nordic UART Service).")
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            HStack {
                Text("CI-V Address")
                Spacer()
                Text("0x")
                    .foregroundStyle(.secondary)
                TextField("A4", text: $rigAddressText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 50)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: rigAddressText) {
                        applyRigAddress()
                    }
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text(
                "CI-V address of your radio. "
                    + "Xiegu G90/X5105: A4. "
                    + "Icom IC-7300: 94."
            )
        }
    }

    private var connectionStatusDot: some View {
        Circle()
            .fill(connectionStatusColor)
            .frame(width: 10, height: 10)
    }

    private func rssiIndicator(_ rssi: Int) -> some View {
        HStack(spacing: 2) {
            let bars = rssiToBars(rssi)
            ForEach(0 ..< 4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(6 + i * 3))
            }
        }
    }

    private func rssiToBars(_ rssi: Int) -> Int {
        if rssi >= -50 {
            return 4
        }
        if rssi >= -65 {
            return 3
        }
        if rssi >= -80 {
            return 2
        }
        if rssi >= -95 {
            return 1
        }
        return 0
    }

    private func applyRigAddress() {
        let cleaned = rigAddressText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")

        guard cleaned.count <= 2,
              let value = UInt8(cleaned, radix: 16)
        else {
            return
        }
        bleRadioService.updateRigAddress(value)
    }
}
