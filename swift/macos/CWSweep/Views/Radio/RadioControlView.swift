import SwiftUI

// MARK: - RadioConnectionFamily

/// Top-level connection family selected by the radio settings picker.
enum RadioConnectionFamily: String, CaseIterable, Identifiable {
    case usb
    case tcpip
    case bridge

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .usb: "USB"
        case .tcpip: "TCP/IP"
        case .bridge: "CW Bridge"
        }
    }
}

// MARK: - RadioControlView

/// Radio connection and control panel.
///
/// Top-level picks one of three connection families (USB / TCP-IP / CW Bridge).
/// USB autodetects the radio on connect; TCP-IP fans out to Flex / SCU-LAN10 /
/// Icom WiFi sub-sections; CW Bridge handles BLE pairing + on-bridge detection.
struct RadioControlView: View {
    // MARK: Internal

    let radioManager: RadioManager
    let flexDiscovery: FlexDiscoveryService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            slotTabStrip
            errorBanner

            switch family {
            case .usb:
                USBRadioSection(
                    radioManager: radioManager,
                    connectionError: $connectionError
                )
            case .tcpip:
                TCPIPRadioSection(
                    radioManager: radioManager,
                    flexDiscovery: flexDiscovery,
                    connectionError: $connectionError
                )
            case .bridge:
                CWBridgeSection(
                    radioManager: radioManager,
                    discovery: bridgeDiscovery,
                    connectionError: $connectionError
                )
            }

            CommandLogSection(commandLog: radioManager.commandLog)
            Spacer()
        }
        .padding(.top)
    }

    // MARK: Private

    @Environment(SerialPortMonitor.self) private var portMonitor
    @Environment(BridgeDiscoveryService.self) private var bridgeDiscovery
    @AppStorage("radio.connectionFamily") private var familyRaw = RadioConnectionFamily.usb.rawValue
    @State private var connectionError: String?
    @State private var showPrefs = false
    @State private var showAddSlot = false

    private var family: RadioConnectionFamily {
        RadioConnectionFamily(rawValue: familyRaw) ?? .usb
    }

    private var familyBinding: Binding<RadioConnectionFamily> {
        Binding(
            get: { family },
            set: { familyRaw = $0.rawValue }
        )
    }

    @ViewBuilder
    private var slotTabStrip: some View {
        let connected = RadioSlot.allCases.filter { radioManager.slots[$0] != nil }
        // Show tabs only when more than one slot is in use, or when the user
        // has explicitly opened the "+ Add Radio" affordance. Single-radio
        // installs see no extra UI.
        if connected.count > 1 || showAddSlot {
            HStack(spacing: 8) {
                ForEach(RadioSlot.allCases) { slot in
                    if radioManager.slots[slot] != nil {
                        slotTabButton(slot: slot, connected: true)
                    }
                }
                if let next = radioManager.nextAvailableSlot(), showAddSlot {
                    slotTabButton(slot: next, connected: false)
                }
                Spacer()
                Button {
                    showAddSlot = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide add-radio tab")
                .opacity(showAddSlot ? 1 : 0)
            }
            .padding(.horizontal)
        } else if radioManager.nextAvailableSlot() != nil, !connected.isEmpty {
            HStack {
                Spacer()
                Button {
                    showAddSlot = true
                    if let next = radioManager.nextAvailableSlot() {
                        radioManager.pendingConnectSlot = next
                    }
                } label: {
                    Label("Add Radio", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
    }

    private var header: some View {
        HStack {
            Text("Radio Control")
                .font(.headline)

            Picker("Connection", selection: familyBinding) {
                ForEach(RadioConnectionFamily.allCases) { fam in
                    Text(fam.label).tag(fam)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)

            Spacer()

            if family == .usb {
                Button("Refresh Ports") {
                    portMonitor.refreshPorts()
                }
            }

            Button {
                showPrefs.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Radio preferences")
            .popover(isPresented: $showPrefs, arrowEdge: .bottom) {
                RadioPreferencesPopover()
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var errorBanner: some View {
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
    }

    @ViewBuilder
    private func slotTabButton(slot: RadioSlot, connected: Bool) -> some View {
        let isFocused = radioManager.focusedSlot == slot
        let title =
            if connected, let state = radioManager.slotStates[slot] {
                "\(slot.label) — \(state.connectedRadioName ?? "Connected")"
            } else {
                "\(slot.label) (new)"
            }
        Button {
            if connected {
                radioManager.setFocusedSlot(slot)
            } else {
                radioManager.pendingConnectSlot = slot
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(connected ? (isFocused ? Color.green : Color.secondary) : Color.orange)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption)
                    .fontWeight(isFocused ? .semibold : .regular)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFocused ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(connected ? "Focus \(slot.label)" : "New radio will bind to \(slot.label)")
    }
}
