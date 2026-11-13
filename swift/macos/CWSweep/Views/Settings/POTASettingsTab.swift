import SwiftUI

// MARK: - POTASettingsTab

struct POTASettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("License") {
                Picker("License Class", selection: $licenseClass) {
                    Text("Technician").tag("Technician")
                    Text("General").tag("General")
                    Text("Extra").tag("Extra")
                }
                Text("Used to show operator privilege boundaries on the band map")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Auto-Spotting") {
                Toggle("Auto self-spot on session start", isOn: $potaAutoSpotOnStart)
                Toggle("Auto self-spot on rove stop change", isOn: $potaAutoSpotOnRoveChange)
            }

            Section("Periodic Re-Spot") {
                Toggle("Enable periodic re-spot", isOn: $potaReSpotEnabled)
                if potaReSpotEnabled {
                    Picker("Re-spot interval", selection: $potaReSpotIntervalMinutes) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                }
            }

            Section("Spot Comment") {
                TextField("Comment template", text: $potaSpotCommentTemplate)
                Text("Tokens: [MODE], [BAND], [PARK], [CALL]")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    @AppStorage("licenseClass") private var licenseClass = "General"
    @AppStorage("potaAutoSpotOnStart") private var potaAutoSpotOnStart = false
    @AppStorage("potaAutoSpotOnRoveChange") private var potaAutoSpotOnRoveChange = false
    @AppStorage("potaReSpotEnabled") private var potaReSpotEnabled = false
    @AppStorage("potaReSpotIntervalMinutes") private var potaReSpotIntervalMinutes = 30
    @AppStorage("potaSpotCommentTemplate") private var potaSpotCommentTemplate = "[MODE] [BAND]"
}
