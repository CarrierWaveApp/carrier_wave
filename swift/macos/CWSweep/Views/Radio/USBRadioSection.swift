import SwiftUI

// MARK: - USBRadioSection

/// USB radio section: list of /dev/cu.* ports, each with a Connect button that
/// runs autodetect (CI-V identify → Kenwood `ID;`) before opening a session.
struct USBRadioSection: View {
    // MARK: Internal

    let radioManager: RadioManager

    @Binding var connectionError: String?

    var body: some View {
        GroupBox("USB Serial") {
            if portMonitor.availablePorts.isEmpty {
                Text("No serial ports detected. Connect a radio via USB.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(portMonitor.availablePorts) { port in
                    USBPortRow(
                        port: port,
                        radioManager: radioManager,
                        connectionError: $connectionError
                    )
                }
                .frame(minHeight: 120, maxHeight: 240)
            }
            if !radioManager.connectionLog.isEmpty {
                connectionLogView
            }
        }
        .padding(.horizontal)
    }

    // MARK: Private

    @Environment(SerialPortMonitor.self) private var portMonitor

    private var connectionLogView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(
                        Array(radioManager.connectionLog.enumerated()),
                        id: \.offset
                    ) { idx, entry in
                        Text(entry)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .id(idx)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 100)
            .onChange(of: radioManager.connectionLog.count) { _, count in
                withAnimation {
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - USBPortRow

struct USBPortRow: View {
    // MARK: Internal

    let port: SerialPortMonitor.SerialPortInfo
    let radioManager: RadioManager

    @Binding var connectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            mainRow
            if let detected = lastDetected {
                detectedSummary(detected)
            }
            if showManualOverride {
                ManualOverrideRow(
                    port: port,
                    radioManager: radioManager,
                    connectionError: $connectionError,
                    onConnected: { showManualOverride = false }
                )
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    @State private var isDetecting = false
    @State private var lastDetected: RadioAutoDetect.Result?
    @State private var showManualOverride = false

    private var isConnected: Bool {
        radioManager.connectedPortPath == port.path
    }

    private var mainRow: some View {
        HStack {
            Image(systemName: isConnected
                ? "antenna.radiowaves.left.and.right"
                : "cable.connector")
                .foregroundStyle(isConnected ? .green : .secondary)

            VStack(alignment: .leading) {
                PortNicknameEditor(port: port)
                Text(port.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                Text(String(format: "%.3f MHz", radioManager.frequency))
                    .font(.body.monospacedDigit())
                Text(radioManager.mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Disconnect") {
                    Task { await radioManager.disconnectAll() }
                }
            } else if isDetecting {
                ProgressView()
                    .controlSize(.small)
                Text("Detecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Connect") {
                    Task { await detectAndConnect() }
                }
                .disabled(radioManager.isConnected)
            }
        }
    }

    private func detectedSummary(_ result: RadioAutoDetect.Result) -> some View {
        let name = result.radioName ?? result.protocolType.rawValue
        return Text("Detected: \(name) • \(result.baudRate) baud • \(result.protocolType.rawValue)")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func detectAndConnect() async {
        isDetecting = true
        connectionError = nil
        defer { isDetecting = false }

        do {
            let result = try await RadioAutoDetect.probe(
                portPath: port.path,
                vendorId: port.vendorId,
                productId: port.productId
            )
            lastDetected = result
            try await connect(profile: result.toProfile(portPath: port.path))
        } catch let error as RadioAutoDetect.DetectError {
            connectionError = error.localizedDescription
            showManualOverride = true
        } catch {
            connectionError = "Connection failed: \(error.localizedDescription)"
        }
    }

    private func connect(profile: RadioProfile) async throws {
        _ = try await radioManager.connect(profile: profile, port: port)
    }
}

// MARK: - RadioAutoDetect.Result → RadioProfile

extension RadioAutoDetect.Result {
    /// Convert a probe result into a RadioProfile suitable for `RadioManager.connect`.
    func toProfile(portPath: String) -> RadioProfile {
        RadioProfile(
            name: radioName ?? "Detected \(protocolType.rawValue)",
            modelId: nil,
            protocolType: protocolType,
            serialPortPath: portPath,
            baudRate: baudRate,
            civAddress: civAddress,
            dtrSignal: protocolType != .elecraft,
            rtsSignal: protocolType != .elecraft
        )
    }
}
