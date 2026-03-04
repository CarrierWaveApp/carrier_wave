import CarrierWaveData
import SwiftUI

// MARK: - ClubLogSettingsView

struct ClubLogSettingsView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "hammer.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("Under Construction")
                        .font(.headline)

                    Text(
                        "Club Log sync is coming in a future update. "
                            + "Stay tuned!"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                Link(destination: URL(string: "https://clublog.org")!) {
                    Label("Visit Club Log Website", systemImage: "arrow.up.right.square")
                }
            }
        }
        .navigationTitle("Club Log")
    }
}
