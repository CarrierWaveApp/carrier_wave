import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "FlexRadioSection")

// MARK: - FlexRadioSection

/// Displays discovered FlexRadio devices on the network with connect/disconnect controls.
struct FlexRadioSection: View {
    // MARK: Internal

    let radioManager: RadioManager
    let flexDiscovery: FlexDiscoveryService

    @Binding var connectionError: String?

    var body: some View {
        GroupBox("FlexRadio (Network)") {
            VStack(alignment: .leading, spacing: 8) {
                if flexDiscovery.discoveredRadios.isEmpty, !showManualEntry {
                    HStack {
                        if flexDiscovery.isListening {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning for Flex radios on the network...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Discovery not running.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Manual IP") {
                            showManualEntry = true
                        }
                        .font(.caption)
                    }
                    .padding(4)
                } else {
                    // Discovered radios
                    ForEach(flexDiscovery.discoveredRadios) { radio in
                        FlexRadioRow(
                            radio: radio,
                            radioManager: radioManager,
                            connectionError: $connectionError
                        )
                    }

                    // Manual entry toggle
                    if !showManualEntry {
                        HStack {
                            Spacer()
                            Button("Connect by IP") {
                                showManualEntry = true
                            }
                            .font(.caption)
                        }
                    }
                }

                // Manual IP entry
                if showManualEntry {
                    FlexManualConnectRow(
                        radioManager: radioManager,
                        connectionError: $connectionError,
                        showManualEntry: $showManualEntry
                    )
                }
            }
            .padding(4)
        }
        .padding(.horizontal)
    }

    // MARK: Private

    @State private var showManualEntry = false
}

// MARK: - FlexRadioRow

/// A single discovered Flex radio with connect/disconnect button
struct FlexRadioRow: View {
    // MARK: Internal

    let radio: DiscoveredFlexRadio
    let radioManager: RadioManager

    @Binding var connectionError: String?

    var body: some View {
        let isThisConnected = radioManager.connectedPortPath == radio.ipAddress
        HStack {
            Image(systemName: isThisConnected
                ? "antenna.radiowaves.left.and.right"
                : "wifi")
                .foregroundStyle(isThisConnected ? .green : .secondary)

            VStack(alignment: .leading) {
                Text(radio.displayName)
                    .font(.body)
                HStack(spacing: 4) {
                    Text(radio.ipAddress)
                    if !radio.callsign.isEmpty {
                        Text("(\(radio.callsign))")
                    }
                    if !radio.version.isEmpty {
                        Text("v\(radio.version)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if isThisConnected {
                Spacer()
                Text(String(format: "%.3f MHz", radioManager.frequency))
                    .font(.body.monospacedDigit())
                Text(radioManager.mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Disconnect") {
                    Task { await radioManager.disconnectAll() }
                }
            } else {
                Spacer()

                Button("Connect") {
                    Task {
                        do {
                            connectionError = nil
                            let model = flexModelForDiscovered(radio)
                            _ = try await radioManager.connectFlex(radio: radio, model: model)
                        } catch {
                            logger.error("Flex connect failed: \(error)")
                            connectionError = "Connection failed: \(error.localizedDescription)"
                        }
                    }
                }
                .disabled(radioManager.isConnected)
            }
        }
    }

    // MARK: Private

    /// Match discovered model string to a known RadioModel
    private func flexModelForDiscovered(_ radio: DiscoveredFlexRadio) -> RadioModel {
        let flexModels = RadioModel.knownModels.filter { $0.protocolType == .flex }
        let match = flexModels.first { radio.model.localizedCaseInsensitiveContains($0.name) }
        return match ?? flexModels[0]
    }
}

// MARK: - FlexManualConnectRow

/// Manual IP address entry for connecting to a Flex radio
struct FlexManualConnectRow: View {
    // MARK: Internal

    let radioManager: RadioManager

    @Binding var connectionError: String?
    @Binding var showManualEntry: Bool

    var body: some View {
        HStack {
            TextField("IP Address", text: $manualHost)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            TextField("Port", value: $manualPort, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)

            Button("Connect") {
                Task {
                    do {
                        connectionError = nil
                        let flexModels = RadioModel.knownModels.filter { $0.protocolType == .flex }
                        let model = flexModels[0]
                        _ = try await radioManager.connectFlexManual(
                            host: manualHost,
                            port: UInt16(manualPort),
                            model: model
                        )
                    } catch {
                        connectionError = "Connection failed: \(error.localizedDescription)"
                    }
                }
            }
            .disabled(manualHost.isEmpty || radioManager.isConnected)

            Button("Cancel") {
                showManualEntry = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    @State private var manualHost = ""
    @State private var manualPort = 4_992
}
