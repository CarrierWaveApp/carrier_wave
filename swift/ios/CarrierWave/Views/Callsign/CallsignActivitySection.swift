import CarrierWaveData
import SwiftUI

// MARK: - CallsignActivitySection

/// Friend activity feed — shows server-synced activity items when friendship is accepted.
struct CallsignActivitySection: View {
    // MARK: Internal

    let callsign: String
    let activityItems: [ActivityItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                if activityItems.count > displayLimit {
                    Button("See All (\(activityItems.count))") {
                        showAll = true
                    }
                    .font(.caption)
                }
            }

            if activityItems.isEmpty {
                ContentUnavailableView(
                    "No Recent Activity",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Activity from \(callsign) will appear here.")
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(displayedItems) { item in
                        ActivityItemRow(item: item)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @State private var showAll = false

    private let displayLimit = 5

    private var displayedItems: [ActivityItem] {
        if showAll {
            return activityItems
        }
        return Array(activityItems.prefix(displayLimit))
    }
}
