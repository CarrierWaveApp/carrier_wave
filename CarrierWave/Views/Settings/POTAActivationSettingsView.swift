import SwiftUI

// MARK: - POTAActivationSettingsView

struct POTAActivationSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            Section {
                Toggle("Auto-spot every 10 minutes", isOn: $potaAutoSpotEnabled)
                Toggle("Prompt for QSY spots", isOn: $potaQSYSpotEnabled)
                Toggle("Post QRT when ending session", isOn: $potaQRTSpotEnabled)
                Toggle(
                    "Record solar & weather at start",
                    isOn: $autoRecordConditions
                )
                Toggle("Poll solar conditions hourly", isOn: $solarPollingEnabled)
                    .onChange(of: solarPollingEnabled) {
                        SolarPollingService.shared.startIfEnabled()
                    }
                Toggle(
                    "Include equipment on brag sheet",
                    isOn: $shareCardIncludeEquipment
                )
                Toggle("Professional Statistician Mode", isOn: $statisticianMode)
            } footer: {
                Text(
                    "Auto-spot posts your frequency to POTA every 10 minutes. "
                        + "QSY spots prompt after frequency or mode changes. "
                        + "QRT spot notifies hunters when you end your activation. "
                        + "Solar & weather records current conditions when starting a session. "
                        + "Hourly polling captures solar conditions in the background "
                        + "for a continuous conditions history graph. "
                        + "Equipment on brag sheet shows radio, antenna, key, and other gear. "
                        + "Statistician mode adds charts to activation details "
                        + "and extra stats to brag sheets."
                )
            }
        }
        .navigationTitle("POTA Activations")
    }

    // MARK: Private

    @AppStorage("potaAutoSpotEnabled") private var potaAutoSpotEnabled = false
    @AppStorage("potaQSYSpotEnabled") private var potaQSYSpotEnabled = true
    @AppStorage("potaQRTSpotEnabled") private var potaQRTSpotEnabled = true
    @AppStorage("autoRecordConditions") private var autoRecordConditions = true
    @AppStorage("solarPollingEnabled") private var solarPollingEnabled = true
    @AppStorage("shareCardIncludeEquipment") private var shareCardIncludeEquipment = true
    @AppStorage("statisticianMode") private var statisticianMode = false
}
