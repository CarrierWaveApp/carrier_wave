import CarrierWaveData
import SwiftData
import SwiftUI

/// Section in Sync Services settings showing a link to Pending Uploads with badge count.
struct PendingUploadsNavigationSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            NavigationLink {
                PendingUploadsView()
            } label: {
                HStack {
                    Label("Pending Uploads", systemImage: "arrow.up.circle.badge.clock")
                    Spacer()
                    if totalPending > 0 {
                        Text("\(totalPending)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange))
                    }
                }
            }
        } footer: {
            if totalPending > 0 {
                Text("QSOs waiting to be uploaded to sync services.")
            }
        }
        .task { loadCount() }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var totalPending = 0

    private let analyzer = PendingUploadAnalyzer()

    private func loadCount() {
        let counts = analyzer.countByService(context: modelContext)
        totalPending = counts.values.reduce(into: 0) { $0 += $1 }
    }
}
