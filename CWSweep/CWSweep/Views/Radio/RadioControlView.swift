import os
import SwiftUI

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RadioControlView")

// MARK: - RadioControlView

/// Radio connection and control panel
struct RadioControlView: View {
    // MARK: Internal

    let radioManager: RadioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Radio Control")
                    .font(.headline)

                Spacer()

                Button("Refresh Ports") {
                    portMonitor.refreshPorts()
                }
            }
            .padding(.horizontal)

            // Connection info
            HStack {
                Text("Using: \(selectedModel.manufacturer) \(selectedModel.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("(\(defaultBaudRate) baud, \(selectedModel.protocolType.rawValue))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Error banner
            if let connectionError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(connectionError)
                        .font(.callout)
                    Spacer()
                    Button("Dismiss") {
                        self.connectionError = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal)
            }

            // Available ports with inline connection state
            GroupBox("Serial Ports") {
                if portMonitor.availablePorts.isEmpty {
                    Text("No serial ports detected. Connect a radio via USB.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    List(portMonitor.availablePorts) { port in
                        let isThisPortConnected = radioManager.connectedPortPath == port.path
                        HStack {
                            Image(systemName: isThisPortConnected
                                ? "antenna.radiowaves.left.and.right"
                                : "cable.connector")
                                .foregroundStyle(isThisPortConnected ? .green : .secondary)

                            VStack(alignment: .leading) {
                                PortNicknameEditor(port: port)
                                Text(port.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if isThisPortConnected {
                                Spacer()

                                Text(String(format: "%.3f MHz", radioManager.frequency))
                                    .font(.body.monospacedDigit())
                                Text(radioManager.mode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button("Disconnect") {
                                    Task {
                                        await radioManager.disconnectAll()
                                    }
                                }
                            } else {
                                Spacer()

                                Button("Connect") {
                                    Task {
                                        let model = selectedModel
                                        var profile = RadioProfile.from(
                                            model: model,
                                            portPath: port.path
                                        )
                                        // Override baud rate if user changed it in Settings
                                        profile.baudRate = defaultBaudRate
                                        logger
                                            .info(
                                                "Connecting to \(port.path) with \(model.name) (\(model.protocolType.rawValue), \(profile.baudRate) baud)"
                                            )
                                        do {
                                            connectionError = nil
                                            _ = try await radioManager.connect(profile: profile, port: port)
                                            logger.info("Connected successfully to \(port.path)")
                                        } catch {
                                            logger.error("Connection failed: \(error)")
                                            connectionError = "Connection failed: \(error.localizedDescription)"
                                        }
                                    }
                                }
                                .disabled(radioManager.isConnected)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)

            // Command log
            GroupBox("Command Log") {
                if radioManager.commandLog.entries.isEmpty {
                    Text("No commands yet. Connect a radio to see TX/RX traffic.")
                        .foregroundStyle(.secondary)
                        .padding(4)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(radioManager.commandLog.entries) { entry in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(
                                            entry.timestamp,
                                            format: .dateTime.hour().minute().second().secondFraction(.fractional(1))
                                        )
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)

                                        Text(directionLabel(entry.direction))
                                            .font(.caption.bold())
                                            .foregroundStyle(directionColor(entry.direction))
                                            .frame(width: 20, alignment: .leading)

                                        Text(entry.text)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    }
                                    .id(entry.id)
                                }
                            }
                            .padding(4)
                        }
                        .onChange(of: radioManager.commandLog.entries.last?.id) { _, newId in
                            if let newId {
                                proxy.scrollTo(newId, anchor: .bottom)
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("\(radioManager.commandLog.entries.count) entries")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button("Clear") {
                        radioManager.commandLog.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                }
            }
            .frame(maxHeight: 200)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
    }

    // MARK: Private

    @Environment(SerialPortMonitor.self) private var portMonitor
    @AppStorage("defaultRadioModel") private var defaultRadioModel = "ic7300"
    @AppStorage("defaultBaudRate") private var defaultBaudRate = 19_200
    @State private var connectionError: String?

    /// Resolve the selected RadioModel from Settings
    private var selectedModel: RadioModel {
        RadioModel.knownModels.first { $0.id == defaultRadioModel }
            ?? RadioModel.knownModels[0]
    }

    private func directionLabel(_ direction: RadioCommandDirection) -> String {
        switch direction {
        case .tx: "TX"
        case .rx: "RX"
        case .status: "--"
        }
    }

    private func directionColor(_ direction: RadioCommandDirection) -> Color {
        switch direction {
        case .tx: .blue
        case .rx: .green
        case .status: .secondary
        }
    }
}
