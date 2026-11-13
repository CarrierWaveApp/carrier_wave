import CarrierWaveData
import SwiftUI

// MARK: - SCU-LAN10 Section

extension RadioSettingsView {
    var sculan10Section: some View {
        Section {
            HStack {
                Text("Host")
                Spacer()
                TextField("192.168.x.x", text: $sculan10IPAddress)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(maxWidth: 160)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            HStack {
                Text("Control Port")
                Spacer()
                TextField("50000", text: $sculan10PortText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 100)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Username")
                Spacer()
                TextField("defaultuser", text: $sculan10Username)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            HStack {
                Text("Password")
                Spacer()
                Group {
                    if showPassword {
                        TextField("password", text: $sculan10Password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("password", text: $sculan10Password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
                .multilineTextAlignment(.trailing)
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
            }

            if !radioService.isConnected {
                Button("Connect") {
                    applySCULAN10Config()
                    radioService.connectSCULAN10()
                }
                .disabled(sculan10IPAddress.isEmpty)
            } else {
                Button("Disconnect") {
                    radioService.disconnectSCULAN10()
                }
            }

            connectionStatusRow
        } header: {
            Text("SCU-LAN10")
        } footer: {
            Text(
                "Yaesu SCU-LAN10 network remote (FTDX101/FTDX10/FT-710). "
                    + "Enter the unit's address and the credentials configured in "
                    + "the SCU-LAN10 setup. The unit allows one client at a time."
            )
        }
    }
}
