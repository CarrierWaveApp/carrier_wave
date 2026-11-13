import CarrierWaveData
import SwiftUI

struct AttributionsView: View {
    // MARK: Internal

    var body: some View {
        List {
            Section {
                Text(
                    "Carrier Wave relies on these amazing amateur radio services. Thank you to the teams behind them!"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section {
                serviceRow(
                    name: "QRZ.com",
                    description:
                    "The world's largest online ham radio community and logbook service",
                    url: "https://www.qrz.com"
                )

                serviceRow(
                    name: "Parks on the Air",
                    description: "Promoting portable amateur radio operations from parks worldwide",
                    url: "https://pota.app"
                )

                serviceRow(
                    name: "Ham2K LoFi",
                    description: "Cloud sync and backup for amateur radio logs",
                    url: "https://ham2k.com"
                )

                serviceRow(
                    name: "HAMRS",
                    description: "Simple, fast logging for amateur radio operators",
                    url: "https://hamrs.app"
                )

                serviceRow(
                    name: "Logbook of The World",
                    description: "ARRL's free QSL confirmation service for amateur radio contacts",
                    url: "https://lotw.arrl.org"
                )
            } header: {
                Text("Ham Radio Services")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("POTA Parks Database")
                        .font(.headline)

                    Text(
                        """
                        Park reference data is downloaded from Parks on the Air (pota.app) \
                        to display park names throughout the app. This data is refreshed \
                        automatically every two weeks.
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("WA7BNM Contest Calendar")
                        .font(.headline)

                    Text(
                        """
                        Contest schedule data from Bruce Horn, WA7BNM's Contest Calendar \
                        (contestcalendar.com). Refreshed every 6 hours.
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("External Data")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built with Apple Technologies")
                        .font(.headline)

                    Text(
                        """
                        Carrier Wave is built entirely with Apple's native frameworks, including SwiftUI, \
                        SwiftData, and Combine.
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Frameworks")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Made with care for the amateur radio community.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("73 de the Carrier Wave team")
                        .font(.subheadline)
                        .italic()
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Attributions")
    }

    // MARK: Private

    private func serviceRow(name: String, description: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}

#Preview {
    NavigationStack {
        AttributionsView()
    }
}
