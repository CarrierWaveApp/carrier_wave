import SwiftUI

/// SDR configuration in Settings
struct SDRSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default Mode", selection: $defaultMode) {
                    Text("CW").tag("CW")
                    Text("LSB").tag("LSB")
                    Text("USB").tag("USB")
                    Text("AM").tag("AM")
                }
            }

            Section("Recording") {
                Toggle("Auto-record when tuned in", isOn: $autoRecord)
                Text("Recordings are saved as CAF files in ~/Documents/WebSDRRecordings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("CW Transcription") {
                Toggle("Enable CW Transcription", isOn: $transcriptionEnabled)
                TextField("cw-swl Server URL", text: $cwswlServerURL)
                    .textFieldStyle(.roundedBorder)
                if cwswlServerURL.isEmpty {
                    Text("Enter the URL of your cw-swl transcription server to enable CW decoding.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    @AppStorage("sdrDefaultMode") private var defaultMode = "CW"
    @AppStorage("sdrAutoRecord") private var autoRecord = true
    @AppStorage("cwswlServerURL") private var cwswlServerURL = ""
    @AppStorage("cwswlTranscriptionEnabled") private var transcriptionEnabled = false
}
