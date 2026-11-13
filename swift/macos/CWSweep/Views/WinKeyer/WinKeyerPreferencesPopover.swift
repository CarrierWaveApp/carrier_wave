import SwiftUI

// MARK: - WinKeyerPreferencesPopover

/// WinKeyer hardware preferences shown from the Keyer Control gear button.
/// Holds the settings that used to live in Settings → WinKeyer (baud,
/// auto-connect, default speed, speed pot range).
struct WinKeyerPreferencesPopover: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("Connection") {
                Picker("Baud Rate", selection: $baudRate) {
                    Text("1200 (default)").tag(1_200)
                    Text("9600").tag(9_600)
                }
                Toggle("Auto-connect on launch", isOn: $autoConnect)
            }

            Section("Speed") {
                Stepper("Default: \(defaultSpeed) WPM", value: $defaultSpeed, in: 5 ... 99)
                Stepper("Pot minimum: \(speedPotMin) WPM", value: $speedPotMin, in: 5 ... 50)
                Stepper("Pot range: \(speedPotRange) WPM", value: $speedPotRange, in: 10 ... 60)
                Text("Pot reads from \(speedPotMin) to \(speedPotMin + speedPotRange) WPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hardware") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supported: K1EL WinKeyer 3")
                    Text("Serial: 8 data bits, 2 stop bits, no parity")
                    Text("USB CDC device — appears as /dev/cu.usbmodem*")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 420)
    }

    // MARK: Private

    @AppStorage("winkeyer.baudRate") private var baudRate = 1_200
    @AppStorage("winkeyer.autoConnect") private var autoConnect = false
    @AppStorage("winkeyer.defaultSpeed") private var defaultSpeed = 25
    @AppStorage("winkeyer.speedPotMin") private var speedPotMin = 10
    @AppStorage("winkeyer.speedPotRange") private var speedPotRange = 35
}
