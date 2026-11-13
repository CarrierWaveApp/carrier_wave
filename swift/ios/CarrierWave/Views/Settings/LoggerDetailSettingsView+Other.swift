import SwiftUI

// MARK: - LoggerDetailSettingsView Sections (extracted)

extension LoggerDetailSettingsView {
    var webSDRSection: some View {
        Section {
            NavigationLink {
                WebSDRRecordingsView()
            } label: {
                Text("Recordings")
            }

            NavigationLink {
                WebSDRFavoritesView()
            } label: {
                Text("Favorites")
            }
        } header: {
            Text("WebSDR")
        }
    }

    var activityLogSection: some View {
        Section("Hunter Log") {
            NavigationLink {
                ActivityLogSettingsView()
            } label: {
                HStack {
                    Text("Hunter Log Settings")
                    Spacer()
                    let count = StationProfileStorage.load().count
                    Text("\(count) profile\(count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
