import SwiftUI

// MARK: - ContestCalendarSettingsView

/// Time-display preferences for the contest calendar.
/// Extracted from Appearance so calendar settings live with the
/// other per-feature screens in Settings > Features.
struct ContestCalendarSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "calendar",
                tint: .red,
                title: "Contest Calendar",
                subtitle: "How contest times are displayed."
            )

            Section {
                Toggle("Show Times in UTC", isOn: $calendarUseUTC)
                if !calendarUseUTC {
                    Toggle("Use 12-Hour Clock", isOn: $calendarUse12Hour)
                }
            } header: {
                Text("Time Display")
            } footer: {
                Text(
                    calendarUseUTC
                        ? "Contest times shown in UTC (Zulu). All contests use UTC scheduling."
                        : "Contest times shown in your local timezone."
                )
            }
        }
        .navigationTitle("Contest Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @AppStorage("contestCalendarUseUTC") private var calendarUseUTC = true
    @AppStorage("contestCalendarUse12Hour") private var calendarUse12Hour = false
}

#Preview {
    NavigationStack {
        ContestCalendarSettingsView()
    }
}
