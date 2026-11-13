import SwiftUI

// MARK: - StatStripCell

/// One cell in a stat strip: a primary value, a label, and an optional
/// "Top X%" percentile chip. Used by both session detail and Hunter Log
/// day summary so the two screens render identical strips.
struct StatStripCell {
    // MARK: Lifecycle

    init(value: String, label: String, percentile: Int? = nil) {
        self.value = value
        self.label = label
        self.percentile = percentile
    }

    // MARK: Internal

    let value: String
    let label: String
    let percentile: Int?
}

// MARK: - SessionStatStrip

/// Horizontal strip of stat cells separated by hairline dividers.
/// Tier 1 component for hero summaries.
struct SessionStatStrip: View {
    // MARK: Internal

    let cells: [StatStripCell]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                if index > 0 {
                    Divider().frame(height: 32)
                }
                statCell(cell)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private func statCell(_ cell: StatStripCell) -> some View {
        VStack(spacing: 3) {
            Text(cell.value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(cell.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let percentile = cell.percentile {
                Text("Top \(percentile)%")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(percentileColor(percentile))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func percentileColor(_ percentile: Int) -> Color {
        if percentile <= 10 {
            return .yellow
        }
        if percentile <= 25 {
            return .green
        }
        if percentile <= 50 {
            return .blue
        }
        return .secondary
    }
}
