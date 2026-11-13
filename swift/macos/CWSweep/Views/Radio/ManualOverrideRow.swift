import SwiftUI

// MARK: - ManualOverrideRow

/// Per-port manual override shown when USB autodetect fails. The user picks a
/// protocol family and baud rate, and the chosen values are used for one
/// connection attempt — no global model picker comes back.
struct ManualOverrideRow: View {
    // MARK: Internal

    let port: SerialPortMonitor.SerialPortInfo
    let radioManager: RadioManager

    @Binding var connectionError: String?

    let onConnected: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DisclosureGroup(isExpanded: $expanded) {
                pickerRow
                connectRow
            } label: {
                Label("Manual override", systemImage: "wrench.adjustable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 24)
    }

    // MARK: Private

    private static let manualProtocols: [RadioProtocolType] = [.civ, .kenwood, .elecraft, .yaesu]
    private static let manualBauds: [Int] = [4_800, 9_600, 19_200, 38_400, 57_600, 115_200]

    @State private var expanded = true
    @State private var manualProto: RadioProtocolType = .civ
    @State private var manualBaud: Int = 19_200
    @State private var manualCIVAddress: String = "94"

    private var pickerRow: some View {
        HStack {
            Picker("Protocol", selection: $manualProto) {
                ForEach(Self.manualProtocols, id: \.self) { proto in
                    Text(proto.rawValue).tag(proto)
                }
            }
            .frame(width: 180)

            Picker("Baud", selection: $manualBaud) {
                ForEach(Self.manualBauds, id: \.self) { baud in
                    Text("\(baud)").tag(baud)
                }
            }
            .frame(width: 140)

            if manualProto == .civ {
                TextField("CI-V (hex)", text: $manualCIVAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            Spacer()
        }
        .font(.caption)
    }

    private var connectRow: some View {
        HStack {
            Spacer()
            Button("Connect with override") {
                Task { await connect() }
            }
            .disabled(radioManager.isConnected)
        }
    }

    private func connect() async {
        connectionError = nil
        let civAddr: UInt8? = manualProto == .civ ? UInt8(manualCIVAddress, radix: 16) : nil
        let profile = RadioProfile(
            name: "Manual \(manualProto.rawValue) on \(port.path)",
            modelId: nil,
            protocolType: manualProto,
            serialPortPath: port.path,
            baudRate: manualBaud,
            civAddress: civAddr,
            dtrSignal: manualProto != .elecraft,
            rtsSignal: manualProto != .elecraft
        )
        do {
            _ = try await radioManager.connect(profile: profile, port: port)
            onConnected()
        } catch {
            connectionError = "Manual connect failed: \(error.localizedDescription)"
        }
    }
}
