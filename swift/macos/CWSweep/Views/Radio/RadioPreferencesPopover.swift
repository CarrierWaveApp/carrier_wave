import SwiftUI

// MARK: - RadioPreferencesPopover

/// Compact preferences shown from the Radio Control gear button. Holds the
/// settings that used to live in Settings → Radio (poll interval,
/// Auto-XIT). Radios you've used before always reconnect (USB and LAN
/// discovery). Connection-specific creds live inline in their
/// respective network sub-sections.
struct RadioPreferencesPopover: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("Connection") {
                Stepper("Poll interval: \(pollIntervalMs) ms",
                        value: $pollIntervalMs, in: 50 ... 1_000, step: 50)
            }

            Section("Auto-XIT") {
                Toggle("Enable when tuning spots", isOn: $autoXITEnabled)
                if autoXITEnabled {
                    Stepper("Offset: \(autoXITOffsetHz) Hz",
                            value: $autoXITOffsetHz, in: -9_999 ... 9_999, step: 10)
                    Text("Transmit frequency will be offset from receive when tuning to a spot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Multi-radio") {
                Toggle("Audio follows focused slot", isOn: $audioFollowsFocus)
                Text("When on, switching focus to Radio A or B also routes the Mac speaker to that slot's RX audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("PTT interlock", isOn: $pttInterlockEnabled)
                Text("Refuses PTT on a slot while another slot is transmitting. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 440)
    }

    // MARK: Private

    @AppStorage("pollIntervalMs") private var pollIntervalMs = 100
    @AppStorage("autoXITEnabled") private var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") private var autoXITOffsetHz = 0
    @AppStorage("radio.audioFollowsFocus") private var audioFollowsFocus = false
    @AppStorage("radio.pttInterlockEnabled") private var pttInterlockEnabled = false
}
