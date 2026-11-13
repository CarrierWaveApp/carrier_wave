import CarrierWaveData
import SwiftUI

// MARK: - RadioSettingsView

/// Settings screen for radio CAT control configuration (BLE, WiFi, and Flex).
struct RadioSettingsView: View {
    @State var radioService: RadioService

    // MARK: - State (accessed by +Sections extension)

    @State var rigAddressText: String = ""
    @State var wifiIPAddress: String = ""
    @State var wifiUsername: String = ""
    @State var wifiPassword: String = ""
    @State var wifiIsAP: Bool = true
    @State var showPassword: Bool = false
    @State var flexIPAddress: String = ""
    @State var flexPortText: String = "4992"
    @State var flexSliceIndex: Int = 0
    @State var smartLinkEmail: String = ""
    @State var smartLinkPassword: String = ""
    @State var sculan10IPAddress: String = ""
    @State var sculan10PortText: String = "50000"
    @State var sculan10Username: String = ""
    @State var sculan10Password: String = ""

    var bleConnectionStatusText: String {
        switch radioService.connectionStatus {
        case .disconnected: "Disconnected"
        case .scanning: "Scanning..."
        case let .connecting(phase): "Connecting: \(phase)"
        case .connected: "Connected"
        case let .error(msg): msg
        }
    }

    var bleConnectionStatusColor: Color {
        switch radioService.connectionStatus {
        case .connected: .green
        case .error: .red
        default: .secondary
        }
    }

    var selectedProtocol: Binding<RigProtocol> {
        Binding(
            get: { radioService.rigProtocol },
            set: { radioService.updateProtocol($0) }
        )
    }

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "antenna.radiowaves.left.and.right",
                tint: .orange,
                title: "Radio",
                subtitle: "Connect to and control your radio."
            )
            experimentalNotice
            transportPickerSection
            switch radioService.transportType {
            case .ble:
                savedDeviceSection
                bridgeInfoSection
                scanSection
            case .wifi:
                wifiSection
            case .flex:
                flexSection
                flexConnectionSection
            case .scuLan10:
                sculan10Section
            }
            if radioService.transportType != .flex,
               radioService.transportType != .scuLan10
            {
                advancedSection
            }
            Section {
                NavigationLink {
                    CWMessageListView()
                } label: {
                    Label("CW Messages", systemImage: "radiowaves.right")
                }
            }
            if !radioService.dataLog.isEmpty {
                dataLogSection
            }
        }
        .navigationTitle("Radio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadState()
        }
        .onDisappear {
            radioService.stopScan()
        }
    }

    func loadState() {
        let addr = UserDefaults.standard.integer(forKey: "bleRadio.rigAddress")
        let address = addr > 0 ? UInt8(addr) : 0xA4
        rigAddressText = String(format: "%02X", address)

        wifiIPAddress = radioService.wifiIPAddress ?? ""
        wifiUsername = (try? KeychainHelper.shared.readString(
            for: RadioService.Keys.wifiKeychainUsername
        )) ?? ""
        wifiPassword = (try? KeychainHelper.shared.readString(
            for: RadioService.Keys.wifiKeychainPassword
        )) ?? ""

        // Determine AP vs Station: 192.168.59.1 is the IC-705 AP address
        if wifiIPAddress == "192.168.59.1" {
            wifiIsAP = true
        } else if !wifiIPAddress.isEmpty {
            wifiIsAP = false
        }

        flexIPAddress = radioService.flexIPAddress ?? ""
        flexPortText = String(radioService.flexPort)
        flexSliceIndex = radioService.flexSliceIndex
        smartLinkEmail = radioService.smartLinkEmail ?? ""

        sculan10IPAddress = radioService.sculan10IPAddress ?? ""
        sculan10PortText = String(radioService.sculan10Port)
        sculan10Username = (try? KeychainHelper.shared.readString(
            for: RadioService.Keys.sculan10KeychainUsername
        )) ?? ""
        sculan10Password = (try? KeychainHelper.shared.readString(
            for: RadioService.Keys.sculan10KeychainPassword
        )) ?? ""
    }

    func applySCULAN10Config() {
        let port = UInt16(sculan10PortText) ?? 50_000
        radioService.saveSCULAN10Config(
            ip: sculan10IPAddress,
            port: port,
            username: sculan10Username,
            password: sculan10Password
        )
    }

    func applyWiFiConfig() {
        let ip = wifiIsAP ? "192.168.59.1" : wifiIPAddress
        radioService.saveWiFiConfig(ip: ip, username: wifiUsername, password: wifiPassword)
    }

    func applyFlexConfig() {
        let port = UInt16(flexPortText) ?? 4_992
        radioService.saveFlexConfig(
            ip: flexIPAddress,
            port: port,
            sliceIndex: flexSliceIndex
        )
    }

    func applyRigAddress() {
        let cleaned = rigAddressText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")

        guard cleaned.count <= 2,
              let value = UInt8(cleaned, radix: 16)
        else {
            return
        }
        radioService.updateRigAddress(value)
    }

    func rssiToBars(_ rssi: Int) -> Int {
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
}
