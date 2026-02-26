import SwiftUI

// MARK: - Stat Grid

extension BragSheetView {
    @ViewBuilder
    var statGrid: some View {
        let config = bragStats.configuration.config(for: bragStats.selectedPeriod)
        let result = bragStats.currentResult
        let heroSet = Set(config.heroStats)
        let gridStats = config.enabledStats.filter { !heroSet.contains($0) }

        if !gridStats.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stats")
                    .font(.headline)

                let columns = [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(gridStats) { stat in
                        BragStatGridCell(
                            stat: stat,
                            value: result?.value(for: stat),
                            isLoading: bragStats.isComputing
                        )
                    }
                }
            }
        }
    }
}

// MARK: - BragStatGridCell

/// Compact card for non-hero stats in the 2-column grid.
struct BragStatGridCell: View {
    // MARK: Internal

    let stat: BragSheetStatType
    let value: BragSheetStatValue?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Stat name
            HStack(spacing: 4) {
                Image(systemName: stat.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(stat.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Inline table stats get custom rendering
            if case .bandTable = displayValue {
                BragInlineTableCell(value: displayValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if case .modeStreakList = displayValue {
                BragInlineTableCell(value: displayValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                gridValueText

                if let subtitle = displayValue.subtitleDisplay {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var displayValue: BragSheetStatValue {
        value ?? .noData
    }

    @ViewBuilder
    private var gridValueText: some View {
        let isNoData = !displayValue.hasData
        let isContactType: Bool = {
            if case .contact = displayValue {
                return true
            }
            if case .callsignCount = displayValue {
                return true
            }
            return false
        }()

        Text(displayValue.heroValue)
            .font(.headline)
            .fontDesign(isContactType ? .monospaced : .default)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .opacity(isNoData || isLoading ? 0.6 : 1.0)
    }
}
