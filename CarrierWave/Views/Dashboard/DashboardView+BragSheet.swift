import SwiftUI

// MARK: - Brag Sheet Dashboard Card

extension DashboardView {
    var bragSheetEntryCard: some View {
        NavigationLink {
            BragSheetView(bragStats: bragSheetStats)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rosette")
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Brag Sheet")
                        .font(.headline)

                    if bragSheetStats.isComputing {
                        Text("Computing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let summary = bragSheetStats.summaryLine {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("View your stats highlights")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
