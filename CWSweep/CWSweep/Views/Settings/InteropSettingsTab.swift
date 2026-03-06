import SwiftUI

/// Settings tab for N1MM+ and WSJT-X interoperability.
struct InteropSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("N1MM+ Broadcast") {
                Toggle("Enable N1MM+ UDP broadcast", isOn: $n1mmEnabled)
                if n1mmEnabled {
                    TextField("Host", text: $n1mmHost)
                    Stepper("Port: \(n1mmPort)", value: $n1mmPort, in: 1_024 ... 65_535)
                }
                Text("Broadcasts contact, radio, and score info to N1MM+ compatible tools.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("WSJT-X") {
                Toggle("Enable WSJT-X listener", isOn: $wsjtxEnabled)
                if wsjtxEnabled {
                    Stepper("Port: \(wsjtxPort)", value: $wsjtxPort, in: 1_024 ... 65_535)
                }
                Text("Listens for decoded messages from WSJT-X for quick logging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    @AppStorage("n1mmEnabled") private var n1mmEnabled = false
    @AppStorage("n1mmHost") private var n1mmHost = "127.0.0.1"
    @AppStorage("n1mmPort") private var n1mmPort = 12_060
    @AppStorage("wsjtxEnabled") private var wsjtxEnabled = false
    @AppStorage("wsjtxPort") private var wsjtxPort = 2_237
}
