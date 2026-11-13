import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "IcomWiFiSection")

// MARK: - IcomWiFiSection

/// Icom WiFi (RS-BA1) connection section. Holds host/credentials inline plus
/// a small radio picker because the CI-V address differs by model.
struct IcomWiFiSection: View {
    // MARK: Internal

    let radioManager: RadioManager

    @Binding var connectionError: String?

    var body: some View {
        GroupBox("Icom WiFi (RS-BA1)") {
            VStack(alignment: .leading, spacing: 8) {
                credentialsForm
                Divider()
                connectionRow
            }
            .padding(8)
        }
        .padding(.horizontal)
    }

    // MARK: Private

    @AppStorage("icomWiFiHost") private var icomWiFiHost = ""
    @AppStorage("icomWiFiUsername") private var icomWiFiUsername = ""
    @AppStorage("icomWiFiPassword") private var icomWiFiPassword = ""
    @AppStorage("icomWiFiModel") private var icomWiFiModel = "ic705-wifi"
    @State private var isConnecting = false

    private var availableModels: [RadioModel] {
        RadioModel.knownModels.filter { $0.protocolType == .icomWiFi }
    }

    private var selectedModel: RadioModel {
        availableModels.first { $0.id == icomWiFiModel } ?? availableModels[0]
    }

    private var credentialsForm: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("Radio").frame(width: 80, alignment: .trailing)
                Picker("", selection: $icomWiFiModel) {
                    ForEach(availableModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Host").frame(width: 80, alignment: .trailing)
                TextField("192.168.59.1", text: $icomWiFiHost)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Username").frame(width: 80, alignment: .trailing)
                TextField("", text: $icomWiFiUsername)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Password").frame(width: 80, alignment: .trailing)
                SecureField("", text: $icomWiFiPassword)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .font(.caption)
    }

    private var connectionRow: some View {
        HStack {
            Image(systemName: radioManager.isConnected ? "wifi" : "wifi.slash")
                .foregroundStyle(radioManager.isConnected ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedModel.name)
                    .font(.body)
                Text(icomWiFiHost.isEmpty ? "Enter host above" : icomWiFiHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if radioManager.isConnected {
                Button("Disconnect") {
                    Task { await radioManager.disconnectAll() }
                }
                .tint(.red)
            } else if isConnecting {
                ProgressView()
                    .controlSize(.small)
                Button("Cancel") { isConnecting = false }
                    .foregroundStyle(.secondary)
            } else {
                Button("Connect") {
                    Task { await connectWithRetry() }
                }
                .disabled(icomWiFiHost.isEmpty || icomWiFiUsername.isEmpty)
            }
        }
    }

    private func connectWithRetry() async {
        guard !icomWiFiHost.isEmpty, !icomWiFiUsername.isEmpty else {
            connectionError = "Enter host and credentials"
            return
        }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        for attempt in 1 ... 3 {
            guard isConnecting else {
                return
            }
            do {
                _ = try await radioManager.connectIcomWiFi(
                    host: icomWiFiHost,
                    username: icomWiFiUsername,
                    password: icomWiFiPassword,
                    model: selectedModel
                )
                return
            } catch {
                logger.warning("Attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < 3, isConnecting {
                    try? await Task.sleep(for: .seconds(2))
                } else {
                    connectionError = error.localizedDescription
                }
            }
        }
    }
}
