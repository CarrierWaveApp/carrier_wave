import CarrierWaveData
import SwiftUI

// MARK: - IcomRadioLabel

enum IcomRadioLabel {
    /// "IC-9700" once we've logged in before, else "Icom radio".
    static func name(for host: String) -> String {
        guard let info = IcomKnownRadios.info(for: host) else {
            return "Icom radio"
        }
        return RadioModel.icomLAN(info).name.replacingOccurrences(of: " (LAN)", with: "")
            .replacingOccurrences(of: " (WiFi)", with: "")
    }
}

// MARK: - IcomConnectButton

/// Connect to an Icom LAN radio by host. Uses Keychain credentials when we
/// have them; otherwise asks once for the radio's Network User ID/password.
struct IcomConnectButton: View {
    // MARK: Internal

    let radioManager: RadioManager
    let host: String
    var title = "Connect"

    @Binding var connectionError: String?

    var body: some View {
        Group {
            if isConnecting {
                ProgressView().controlSize(.small)
            } else {
                Button(title) { tapped() }
                    .disabled(host.isEmpty)
            }
        }
        .sheet(isPresented: $askForCredentials) {
            IcomCredentialsSheet(radioManager: radioManager, host: host) {
                askForCredentials = false
            }
        }
    }

    // MARK: Private

    @State private var isConnecting = false
    @State private var askForCredentials = false

    private func tapped() {
        guard let saved = IcomKnownRadios.credentials(for: host) else {
            askForCredentials = true
            return
        }
        isConnecting = true
        connectionError = nil
        Task {
            defer { isConnecting = false }
            do {
                try await radioManager.connectIcomLAN(host: host, credentials: saved)
            } catch let IcomWiFiError.authenticationFailed(stage) where stage.contains("rejected") {
                // Saved login no longer works (changed on the radio): ask again.
                askForCredentials = true
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }
}

// MARK: - IcomCredentialsSheet

/// One-time login prompt. On success the credentials go to the Keychain.
struct IcomCredentialsSheet: View {
    // MARK: Internal

    let radioManager: RadioManager
    let host: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log in to \(IcomRadioLabel.name(for: host)) at \(host)")
                .font(.headline)
            Text(
                "Use the radio's Network User ID and password (MENU › SET › Network). "
                    + "Sweep saves them in your Keychain."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("User ID", text: $username)
                SecureField("Password", text: $password)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                    .keyboardShortcut(.cancelAction)
                if isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Connect") { Task { await connect() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(username.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            username = IcomKnownRadios.credentials(for: host)?.username ?? legacyUsername
        }
    }

    // MARK: Private

    /// Username from the old manual form (pre-discovery), used as a prefill.
    @AppStorage("icomWiFiUsername") private var legacyUsername = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isConnecting = false

    private func connect() async {
        isConnecting = true
        error = nil
        defer { isConnecting = false }
        // The radio often drops the first login packets; try a few times.
        for attempt in 1 ... 3 {
            do {
                try await radioManager.connectIcomLAN(
                    host: host,
                    credentials: IcomLANCredentials(username: username, password: password)
                )
                // The old form kept the password in plain UserDefaults.
                UserDefaults.standard.removeObject(forKey: "icomWiFiPassword")
                onDone()
                return
            } catch {
                if attempt == 3 {
                    self.error = error.localizedDescription
                } else {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }
}

// MARK: - IcomFoundBanner

/// "Found IC-9700 on the network — Connect?" at the top of the Radio panel
/// for each discovered Icom radio that isn't connected.
struct IcomFoundBanner: View {
    // MARK: Internal

    let radioManager: RadioManager

    @Binding var connectionError: String?

    var body: some View {
        ForEach(pending) { radio in
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.tint)
                Text("Found \(IcomRadioLabel.name(for: radio.host)) on the network (\(radio.host)). Connect?")
                    .font(.callout)
                Spacer()
                IcomConnectButton(radioManager: radioManager, host: radio.host, connectionError: $connectionError)
                Button {
                    dismissed.insert(radio.host)
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

    @State private var dismissed: Set<String> = []

    private var pending: [DiscoveredIcomRadio] {
        radioManager.icomDiscovery.radios.filter {
            !dismissed.contains($0.host) && !radioManager.isConnectedToIcom(host: $0.host)
        }
    }
}
