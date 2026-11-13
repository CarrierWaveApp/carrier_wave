import SwiftUI

// MARK: - SatelliteDuplexSheet

/// Two-radio FM satellite tuning: bind a CW Bridge to the uplink and one
/// to the downlink handheld, pick auto or manual-downlink Doppler, set the
/// uplink CTCSS for the selected bird, and start/stop the tuning loop.
struct SatelliteDuplexSheet: View {
    // MARK: Internal

    let model: SatelliteTrackerModel

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                RadioLinkSection(link: controller.uplink, title: "Uplink radio", icon: "arrow.up")
                RadioLinkSection(link: controller.downlink, title: "Downlink radio", icon: "arrow.down")
                swapSection
                modeSection
                toneSection
            }
            .navigationTitle("Duplex Radios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if let norad = model.selectedNoradID {
                toneText = Self.formatTone(controller.toneTenthsHz(for: norad))
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var controller = SatelliteDuplexController.shared
    @State private var toneText = ""

    private var statusSection: some View {
        Section {
            if let name = model.selectedPosition?.name {
                LabeledContent("Satellite", value: name)
            } else {
                Text("Select a satellite on the map first.")
                    .foregroundStyle(.secondary)
            }
            if let description = controller.readout.transmitterDescription {
                LabeledContent("Transmitter", value: description)
            }
            frequencyRow("Downlink", predicted: controller.readout.predictedDownlinkHz,
                         commanded: controller.readout.commandedDownlinkHz,
                         actualMHz: controller.downlink.frequencyMHz)
            frequencyRow("Uplink", predicted: controller.readout.predictedUplinkHz,
                         commanded: controller.readout.commandedUplinkHz,
                         actualMHz: controller.uplink.frequencyMHz)
            if let offset = controller.readout.manualOffsetHz {
                LabeledContent("Your correction", value: String(format: "%+d Hz", offset))
            }
            if let shift = controller.readout.dopplerShiftHz {
                LabeledContent("Doppler", value: String(format: "%+.1f kHz", Double(shift) / 1_000))
            }
            if let message = controller.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let error = controller.uplink.lastError ?? controller.downlink.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                if controller.isTuning {
                    controller.stop()
                } else {
                    controller.start(model: model)
                }
            } label: {
                Label(
                    controller.isTuning ? "Stop tuning" : "Start tuning",
                    systemImage: controller.isTuning ? "stop.circle.fill" : "play.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isTuning ? .red : .orange)
            .disabled(model.selectedNoradID == nil || !controller.hasBothRadios)
        } header: {
            Text("Tuning")
        } footer: {
            if !controller.hasBothRadios {
                Text("Bind a CW Bridge to each radio below to enable tuning.")
            }
        }
    }

    private var swapSection: some View {
        Section {
            Button {
                controller.swapRoles()
            } label: {
                Label("Swap uplink and downlink", systemImage: "arrow.left.arrow.right")
            }
            .disabled(!controller.uplink.isConfigured && !controller.downlink.isConfigured)
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $controller.mode) {
                ForEach(SatelliteDuplexController.TuningMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(controller.mode.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Doppler")
        }
    }

    private var toneSection: some View {
        Section {
            HStack {
                TextField("67.0", text: $toneText)
                    .keyboardType(.decimalPad)
                    .onSubmit(commitTone)
                Text("Hz")
                    .foregroundStyle(.secondary)
                Button("Apply", action: commitTone)
                    .disabled(model.selectedNoradID == nil)
            }
        } header: {
            Text("Uplink CTCSS")
        } footer: {
            Text(
                "Sent to the uplink radio when tuning starts. Leave empty for no tone. "
                    + "SO-50 and the ISS repeater use 67.0 Hz."
            )
        }
    }

    private func frequencyRow(_ title: String, predicted: UInt64?, commanded: UInt64?,
                              actualMHz: Double?) -> some View
    {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(predicted.map(Self.formatHz) ?? "—")
                    .font(.body.monospacedDigit().weight(.semibold))
            }
            HStack {
                Text(commanded.map { "sent \(Self.formatHz($0))" } ?? "not sent")
                Spacer()
                Text(actualMHz.map { String(format: "radio %.5f", $0) } ?? "radio —")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private static func formatHz(_ hz: UInt64) -> String {
        String(format: "%.5f", Double(hz) / 1_000_000)
    }

    private static func formatTone(_ tenths: Int?) -> String {
        guard let tenths, tenths > 0 else {
            return ""
        }
        return String(format: "%.1f", Double(tenths) / 10)
    }

    private func commitTone() {
        guard let norad = model.selectedNoradID else {
            return
        }
        let trimmed = toneText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            controller.setTone(tenthsHz: nil, for: norad)
        } else if let hz = Double(trimmed) {
            controller.setTone(tenthsHz: Int((hz * 10).rounded()), for: norad)
        }
        toneText = Self.formatTone(controller.toneTenthsHz(for: norad))
    }
}

// MARK: - RadioLinkSection

/// Bridge picker for one `RadioLink`: saved device + live status, scan
/// results to bind, forget.
private struct RadioLinkSection: View {
    // MARK: Internal

    let link: RadioLink
    let title: String
    let icon: String

    var body: some View {
        Section {
            if let name = link.savedDeviceName {
                LabeledContent(name, value: statusText)
                if let radio = link.detectedRadio {
                    LabeledContent("Radio", value: radio)
                } else if link.isConnected {
                    LabeledContent("Radio", value: link.bridgeUSBConnected ? "Detecting…" : "No USB device")
                }
                if link.isConnected {
                    Button("Disconnect") { link.disconnect() }
                } else {
                    Button("Connect") { link.connect() }
                }
                Button("Forget bridge", role: .destructive) { link.forgetDevice() }
            } else {
                Text("No bridge bound")
                    .foregroundStyle(.secondary)
            }
            if link.isScanning {
                HStack {
                    ProgressView()
                    Text("Scanning…")
                    Spacer()
                    Button("Stop") { link.stopScan() }
                }
                ForEach(link.discoveredDevices) { device in
                    Button {
                        link.selectDevice(device)
                    } label: {
                        HStack {
                            Text(device.name)
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Button {
                    link.startScan()
                } label: {
                    Label(
                        link.savedDeviceName == nil ? "Scan for bridge" : "Change bridge",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }
            }
        } header: {
            Label(title, systemImage: icon)
        }
    }

    // MARK: Private

    private var statusText: String {
        switch link.connectionStatus {
        case .disconnected: "Disconnected"
        case .scanning: "Scanning"
        case let .connecting(phase): "Connecting (\(phase))"
        case .connected: "Connected"
        case let .error(message): message
        }
    }
}
