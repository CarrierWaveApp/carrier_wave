import SwiftUI

// MARK: - IcomWiFiSection

/// Icom LAN/WiFi (RS-BA1) radios. Radios with Network Control on are found
/// automatically; the model is read from the radio at login, so there is no
/// picker. A collapsed manual-address form covers radios discovery can't
/// reach (another subnet, VPN).
struct IcomWiFiSection: View {
    // MARK: Internal

    let radioManager: RadioManager

    @Binding var connectionError: String?

    var body: some View {
        GroupBox("Icom LAN / WiFi") {
            VStack(alignment: .leading, spacing: 8) {
                discoveredList
                Divider()
                DisclosureGroup("Enter address manually", isExpanded: $showManual) {
                    manualForm
                }
                .font(.caption)
            }
            .padding(8)
        }
        .padding(.horizontal)
    }

    // MARK: Private

    @AppStorage("icomWiFiHost") private var manualHost = ""
    @State private var showManual = false

    private var discovery: IcomDiscoveryService {
        radioManager.icomDiscovery
    }

    @ViewBuilder
    private var discoveredList: some View {
        if discovery.radios.isEmpty {
            HStack {
                if discovery.isScanning {
                    ProgressView().controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(discovery.isScanning ? "Looking for Icom radios…" : "No Icom radios found.")
                    Text("Turn on MENU › SET › Network › Network Control on the radio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Scan Now") { Task { await discovery.scanOnce() } }
                    .disabled(discovery.isScanning)
            }
        } else {
            ForEach(discovery.radios) { radio in
                radioRow(host: radio.host)
            }
        }
    }

    private var manualForm: some View {
        HStack {
            TextField("Radio IP address", text: $manualHost)
                .textFieldStyle(.roundedBorder)
            IcomConnectButton(
                radioManager: radioManager,
                host: manualHost.trimmingCharacters(in: .whitespaces),
                connectionError: $connectionError
            )
        }
        .padding(.top, 4)
    }

    private func radioRow(host: String) -> some View {
        let connected = radioManager.isConnectedToIcom(host: host)
        return HStack {
            Image(systemName: connected ? "wifi" : "wifi.slash")
                .foregroundStyle(connected ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(IcomRadioLabel.name(for: host))
                Text(host).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if connected {
                Button("Disconnect") {
                    Task { await radioManager.disconnectIcom(host: host) }
                }
                .tint(.red)
            } else {
                IcomConnectButton(radioManager: radioManager, host: host, connectionError: $connectionError)
            }
        }
    }
}
