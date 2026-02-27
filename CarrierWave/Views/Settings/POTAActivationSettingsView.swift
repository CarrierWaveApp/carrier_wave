import SwiftUI

// MARK: - POTAActivationSettingsView

struct POTAActivationSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            spottingSection
            qrqCrewSection
        }
        .navigationTitle("POTA Activations")
    }

    // MARK: Private

    @AppStorage("potaAutoSpotEnabled") private var potaAutoSpotEnabled = false
    @AppStorage("potaQSYSpotEnabled") private var potaQSYSpotEnabled = true
    @AppStorage("potaQRTSpotEnabled") private var potaQRTSpotEnabled = true
    @AppStorage("potaRoveQRTMessage") private var potaRoveQRTMessage = "QRT moving to next park"

    private var spottingSection: some View {
        Section {
            Toggle("Auto-spot every 10 minutes", isOn: $potaAutoSpotEnabled)
            Toggle("Prompt for QSY spots", isOn: $potaQSYSpotEnabled)
            Toggle("Post QRT when ending session", isOn: $potaQRTSpotEnabled)
            VStack(alignment: .leading, spacing: 4) {
                Text("Rove QRT message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("QRT moving to next park", text: $potaRoveQRTMessage)
                    .textInputAutocapitalization(.characters)
            }
        } header: {
            Text("Spotting")
        } footer: {
            Text(
                "Auto-spot posts your frequency to POTA every 10 minutes. "
                    + "QSY spots prompt after frequency or mode changes. "
                    + "QRT spot notifies hunters when you end your activation."
            )
        }
    }

    private var qrqCrewSection: some View {
        Section {
            Text("QRQ Crew spots are posted on UTC Fridays when both operators are members.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            Text("QRQ Crew")
        } footer: {
            Text(
                "CW speed is auto-populated from RBN. "
                    + "Spots are only posted at \(QRQCrewService.minimumWPM)+ WPM."
            )
        }
    }
}
