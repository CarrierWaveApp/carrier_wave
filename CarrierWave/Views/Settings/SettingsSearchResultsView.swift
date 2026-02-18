import SwiftUI

// MARK: - SettingsSearchResultsView

struct SettingsSearchResultsView<Destination: View>: View {
    let results: [SettingsSearchItem]
    @ViewBuilder var destination: (SettingsSearchDestination) -> Destination

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search
        } else {
            ForEach(results) { item in
                NavigationLink {
                    destination(item.destination)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.breadcrumb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
