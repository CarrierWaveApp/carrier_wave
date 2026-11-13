import CarrierWaveData
import SwiftUI

// MARK: - RadioSettingsView Sections

extension RadioSettingsView {
    // MARK: - Experimental Notice

    var experimentalNotice: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Experimental Feature")
                            .font(.subheadline.weight(.semibold))
                        ExperimentalBadge(feature: .radioControl)
                    }
                    Text(
                        "Radio CAT control via BLE, WiFi, Flex SmartSDR, or Yaesu SCU-LAN10 "
                            + "requires compatible hardware. "
                            + "This feature is under active development and may not work "
                            + "with all radios."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Transport Picker

    var transportPickerSection: some View {
        Section {
            Picker("Transport", selection: Binding(
                get: { radioService.transportType },
                set: { radioService.transportType = $0 }
            )) {
                ForEach(RadioService.TransportType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - BLE: Saved Device

    @ViewBuilder
    var savedDeviceSection: some View {
        if let name = radioService.savedDeviceName {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                        Text(bleConnectionStatusText)
                            .font(.caption)
                            .foregroundStyle(bleConnectionStatusColor)
                    }
                    Spacer()
                    bleConnectionStatusDot
                }

                if !radioService.isConnected {
                    Button("Connect") {
                        radioService.connectToSavedDevice()
                    }
                } else {
                    Button("Disconnect") {
                        radioService.disconnect()
                    }
                }

                Button("Forget Device", role: .destructive) {
                    radioService.forgetDevice()
                }
            } header: {
                Text("Saved Device")
            }
        }
    }

    // MARK: - BLE: Bridge Info

    @ViewBuilder
    var bridgeInfoSection: some View {
        if radioService.isConnected, radioService.bridgeIsFramed {
            Section {
                if let fwVersion = radioService.bridgeFirmwareVersion {
                    HStack {
                        Text("Firmware")
                        Spacer()
                        Text("v\(fwVersion)")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("USB")
                    Spacer()
                    Text(radioService.bridgeUSBConnected ? "Connected" : "Disconnected")
                        .foregroundStyle(radioService.bridgeUSBConnected ? .green : .secondary)
                }

                if radioService.bridgeDetecting {
                    HStack {
                        Text("Detecting radio...")
                        Spacer()
                        ProgressView()
                    }
                } else if let radio = radioService.bridgeDetectedRadio {
                    HStack {
                        Text("Radio")
                        Spacer()
                        Text(radio)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Re-detect Radio") {
                    Task {
                        if let bridge = radioService.bridgeProtocol {
                            try? await bridge.requestDetection()
                        }
                    }
                }
                .disabled(!radioService.bridgeUSBConnected)
            } header: {
                Text("CW Bridge")
            }
        }
    }

    // MARK: - BLE: Scan

    var scanSection: some View {
        Section {
            Button {
                if radioService.isScanning {
                    radioService.stopScan()
                } else {
                    radioService.startScan()
                }
            } label: {
                HStack {
                    Text(radioService.isScanning ? "Stop Scanning" : "Scan for Devices")
                    if radioService.isScanning {
                        Spacer()
                        ProgressView()
                    }
                }
            }

            ForEach(radioService.discoveredDevices) { device in
                Button {
                    radioService.selectDevice(device)
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

    // MARK: - WiFi Section

    var wifiSection: some View {
        Section {
            Picker("Mode", selection: $wifiIsAP) {
                Text("Access Point").tag(true)
                Text("Station").tag(false)
            }

            if wifiIsAP {
                HStack {
                    Text("IP Address")
                    Spacer()
                    Text("192.168.59.1")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text("IP Address")
                    Spacer()
                    TextField("192.168.x.x", text: $wifiIPAddress)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 140)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            HStack {
                Text("Username")
                Spacer()
                TextField("admin", text: $wifiUsername)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            HStack {
                Text("Password")
                Spacer()
                Group {
                    if showPassword {
                        TextField("password", text: $wifiPassword)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("password", text: $wifiPassword)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
                .multilineTextAlignment(.trailing)
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
            }

            if !radioService.isConnected {
                Button("Connect") {
                    applyWiFiConfig()
                    radioService.connectWiFi()
                }
            } else {
                Button("Disconnect") {
                    radioService.disconnectWiFi()
                }
            }

            connectionStatusRow
        } header: {
            Text("WiFi")
        } footer: {
            Text(
                "Access Point mode connects to your radio's built-in hotspot (IC-705 default). "
                    + "Station mode connects to a radio on your local network."
            )
        }
    }

    // MARK: - Advanced

    private var isWiFiTransport: Bool {
        radioService.transportType == .wifi
    }

    var advancedSection: some View {
        Section {
            if isWiFiTransport {
                HStack {
                    Text("Protocol")
                    Spacer()
                    Text("CI-V (Icom)")
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Protocol", selection: selectedProtocol) {
                    ForEach(RigProtocol.allCases, id: \.self) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
            }

            if radioService.rigProtocol == .civ {
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
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text(
                isWiFiTransport
                    ? "WiFi transport uses Icom RS-BA1 protocol, which requires CI-V."
                    : "Protocol is auto-detected from your radio. "
                    + "Override here if needed."
            )
        }
    }

    // MARK: - Data Log

    private static let logTimeFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt
    }()

    var dataLogSection: some View {
        Section {
            ForEach(radioService.dataLog) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(Self.logTimeFmt.string(from: entry.timestamp))
                            .foregroundStyle(.tertiary)
                        Text(entry.direction == .sent ? "TX" : "RX")
                            .foregroundStyle(
                                entry.direction == .error ? .red :
                                    entry.direction == .sent ? .blue : .green
                            )
                        Text(entry.message)
                    }
                    .font(.caption2.monospaced())
                    if let hex = entry.hexData {
                        Text(hex)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Copy Log") {
                let text = radioService.dataLog.map { entry in
                    let ts = Self.logTimeFmt.string(from: entry.timestamp)
                    let hex = entry.hexData ?? ""
                    return "\(ts) \(entry.message) \(hex)"
                }.joined(separator: "\n")
                UIPasteboard.general.string = text
            }
            Button("Clear Log", role: .destructive) {
                radioService.clearLog()
            }
        } header: {
            Text("Data Log")
        }
    }

    // MARK: - Shared Helpers

    var bleConnectionStatusDot: some View {
        Circle()
            .fill(bleConnectionStatusColor)
            .frame(width: 10, height: 10)
    }

    var connectionStatusRow: some View {
        HStack {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 10, height: 10)
            Text(connectionStatusText)
                .font(.caption)
                .foregroundStyle(connectionStatusColor)
        }
    }

    private var connectionStatusText: String {
        switch radioService.connectionStatus {
        case .disconnected: "Disconnected"
        case .scanning: "Scanning..."
        case let .connecting(phase): "Connecting: \(phase)"
        case .connected: "Connected"
        case let .error(msg): msg
        }
    }

    private var connectionStatusColor: Color {
        switch radioService.connectionStatus {
        case .connected: .green
        case .error: .red
        default: .secondary
        }
    }

    func rssiIndicator(_ rssi: Int) -> some View {
        HStack(spacing: 2) {
            let bars = rssiToBars(rssi)
            ForEach(0 ..< 4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < bars ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 4, height: CGFloat(6 + index * 3))
            }
        }
    }
}
