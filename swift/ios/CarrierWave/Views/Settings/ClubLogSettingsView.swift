import SwiftUI

// MARK: - ClubLogSettingsView

struct ClubLogSettingsView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Label(
                        "Coming Soon",
                        systemImage: "hammer.fill"
                    )
                    .foregroundStyle(.orange)
                    Spacer()
                }

                Text(
                    "Club Log integration is under development. "
                        + "Upload QSOs to Club Log for DXCC credit "
                        + "and DXpedition tracking."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } header: {
                Text("Status")
            }

            Section {
                Link(
                    destination: URL(string: "https://clublog.org")!
                ) {
                    Label(
                        "Visit Club Log Website",
                        systemImage: "arrow.up.right.square"
                    )
                }
            }
        }
        .navigationTitle("Club Log")
    }
}
