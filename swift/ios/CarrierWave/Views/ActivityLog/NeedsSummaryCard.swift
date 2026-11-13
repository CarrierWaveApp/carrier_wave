// Needs Summary Card
//
// Banner shown above the spot list when operator needs are on the air.
// Displays a compact one-line summary with counts per category.

import SwiftUI

// MARK: - NeedsSummaryCard

struct NeedsSummaryCard: View {
    let summary: NeedsOnAirSummary
    let onTap: () -> Void

    var body: some View {
        guard summary.hasMatches else {
            return AnyView(EmptyView())
        }

        return AnyView(
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.yellow)

                    Text(summary.summaryText)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(summary.totalMatchedSpots)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        )
    }
}
