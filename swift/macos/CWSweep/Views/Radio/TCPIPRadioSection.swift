import SwiftUI

// MARK: - TCPIPRadioKind

/// Sub-protocol within the TCP/IP family.
enum TCPIPRadioKind: String, CaseIterable, Identifiable {
    case flex
    case sculan10
    case icomWiFi

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .flex: "FlexRadio"
        case .sculan10: "Yaesu SCU-LAN10"
        case .icomWiFi: "Icom WiFi (RS-BA1)"
        }
    }
}

// MARK: - TCPIPRadioSection

/// Network connection section. Sub-picker chooses Flex / SCU-LAN10 / Icom WiFi;
/// each child renders its own discovery or credentials UI.
struct TCPIPRadioSection: View {
    // MARK: Internal

    let radioManager: RadioManager
    let flexDiscovery: FlexDiscoveryService

    @Binding var connectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            kindPicker

            switch kind {
            case .flex:
                FlexRadioSection(
                    radioManager: radioManager,
                    flexDiscovery: flexDiscovery,
                    connectionError: $connectionError
                )
            case .sculan10:
                SCULAN10Section(
                    radioManager: radioManager,
                    connectionError: $connectionError
                )
            case .icomWiFi:
                IcomWiFiSection(
                    radioManager: radioManager,
                    connectionError: $connectionError
                )
            }
        }
    }

    // MARK: Private

    @AppStorage("radio.tcpipKind") private var kindRaw = TCPIPRadioKind.flex.rawValue

    private var kind: TCPIPRadioKind {
        TCPIPRadioKind(rawValue: kindRaw) ?? .flex
    }

    private var kindPicker: some View {
        Picker("Network type", selection: Binding(
            get: { kind },
            set: { kindRaw = $0.rawValue }
        )) {
            ForEach(TCPIPRadioKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal)
    }
}
