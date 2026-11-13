import CarrierWaveData
import SwiftUI

// MARK: - Flex & SmartLink Sections

extension RadioSettingsView {
    // MARK: - Flex Section

    var flexSection: some View {
        Section {
            Toggle("SmartLink (Remote)", isOn: Binding(
                get: { radioService.useSmartLink },
                set: { radioService.useSmartLink = $0 }
            ))

            Picker("Slice", selection: $flexSliceIndex) {
                ForEach(0 ..< 8, id: \.self) { idx in
                    Text("Slice \(idx)").tag(idx)
                }
            }

            connectionStatusRow
        } header: {
            Text("FlexRadio SmartSDR")
        }
    }

    @ViewBuilder
    var flexConnectionSection: some View {
        if radioService.useSmartLink {
            smartLinkSection
        } else {
            flexLANSection
        }
    }

    var flexLANSection: some View {
        Section {
            HStack {
                Text("IP Address")
                Spacer()
                TextField("192.168.x.x", text: $flexIPAddress)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 160)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            HStack {
                Text("Port")
                Spacer()
                TextField("4992", text: $flexPortText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 80)
                    .multilineTextAlignment(.trailing)
            }

            if !radioService.isConnected {
                Button("Connect") {
                    applyFlexConfig()
                    radioService.connectFlex()
                }
            } else {
                Button("Disconnect") {
                    radioService.disconnect()
                }
            }
        } header: {
            Text("LAN Connection")
        } footer: {
            Text("Direct TCP connection to a FlexRadio on your local network.")
        }
    }

    // MARK: - SmartLink

    var smartLinkSection: some View {
        Section {
            if radioService.isSmartLinkLoggedIn {
                smartLinkLoggedInContent
            } else {
                smartLinkLoginContent
            }
        } header: {
            Text("SmartLink")
        } footer: {
            Text("Log in with your FlexRadio SmartLink account to connect remotely.")
        }
    }

    private var smartLinkLoginContent: some View {
        Group {
            HStack {
                Text("Email")
                Spacer()
                TextField("email@example.com", text: $smartLinkEmail)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .frame(maxWidth: 200)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            HStack {
                Text("Password")
                Spacer()
                SecureField("password", text: $smartLinkPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .multilineTextAlignment(.trailing)
            }

            Button("Log In") {
                radioService.smartLinkLogin(
                    email: smartLinkEmail,
                    password: smartLinkPassword
                )
                smartLinkPassword = ""
            }
            .disabled(smartLinkEmail.isEmpty || smartLinkPassword.isEmpty)
        }
    }

    private var smartLinkLoggedInContent: some View {
        Group {
            smartLinkAccountRow

            if radioService.isSmartLinkConnecting {
                HStack {
                    Text("Discovering radios...")
                    Spacer()
                    ProgressView()
                }
            } else if radioService.smartLinkRadios.isEmpty {
                Button("Find Radios") {
                    radioService.smartLinkRefreshAndDiscover()
                }
            }

            ForEach(radioService.smartLinkRadios) { radio in
                smartLinkRadioRow(radio)
            }

            Button("Log Out", role: .destructive) {
                radioService.smartLinkLogout()
            }
        }
    }

    private var smartLinkAccountRow: some View {
        HStack {
            Text("Account")
            Spacer()
            Text(radioService.smartLinkEmail ?? "")
                .foregroundStyle(.secondary)
        }
    }

    private func smartLinkRadioRow(_ radio: SmartLinkRadio) -> some View {
        Button {
            applyFlexConfig()
            radioService.connectSmartLink(radio: radio)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(radio.displayName)
                        .foregroundStyle(.primary)
                    Text(radio.status)
                        .font(.caption)
                        .foregroundStyle(
                            radio.status == "Available" ? .green : .orange
                        )
                }
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
