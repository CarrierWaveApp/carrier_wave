import SwiftUI

// MARK: - USBFoundBanner

/// "Found Icom IC-7300 on USB (port). Connect?" atop the Radio panel for each
/// radio `USBRadioDiscovery` identified on a port that isn't connected.
struct USBFoundBanner: View {
    // MARK: Internal

    let radioManager: RadioManager

    @Binding var connectionError: String?

    var body: some View {
        ForEach(pending) { radio in
            HStack(spacing: 8) {
                Image(systemName: "cable.connector")
                    .foregroundStyle(.tint)
                Text("Found \(radio.displayName) on USB (\(portMonitor.displayName(for: radio.port))). Connect?")
                    .font(.callout)
                Spacer()
                if connecting == radio.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Connect") { Task { await connect(radio) } }
                }
                Button {
                    radioManager.usbDiscovery.dismiss(path: radio.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Not now")
            }
            .padding(10)
            .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
        }
    }

    // MARK: Private

    @Environment(SerialPortMonitor.self) private var portMonitor
    @State private var connecting: String?

    private var pending: [DetectedUSBRadio] {
        radioManager.usbDiscovery.found.filter { radioManager.slotForPortPath($0.port.path) == nil }
    }

    private func connect(_ radio: DetectedUSBRadio) async {
        connecting = radio.id
        connectionError = nil
        defer { connecting = nil }
        do {
            _ = try await radioManager.connect(
                profile: radio.result.toProfile(portPath: radio.port.path),
                port: radio.port
            )
            radioManager.usbDiscovery.dismiss(path: radio.id)
        } catch {
            connectionError = "Connection failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - USBRadioDiscoveryModifier

/// Runs USB radio discovery at launch and on every hot-plug change.
private struct USBRadioDiscoveryModifier: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content
            .task { await radioManager.autoConnect(ports: portMonitor.availablePorts) }
            .onChange(of: portMonitor.availablePorts) { _, ports in
                Task { await radioManager.autoConnect(ports: ports) }
            }
    }

    // MARK: Private

    @Environment(SerialPortMonitor.self) private var portMonitor
    @Environment(RadioManager.self) private var radioManager
}

extension View {
    func discoversUSBRadios() -> some View {
        modifier(USBRadioDiscoveryModifier())
    }
}
