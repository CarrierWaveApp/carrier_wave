import CarrierWaveData
import SwiftUI

// MARK: - Hero Section

extension BragSheetView {
    @ViewBuilder
    var heroSection: some View {
        let config = bragStats.configuration.config(for: bragStats.selectedPeriod)
        let result = bragStats.currentResult

        if !config.heroStats.isEmpty {
            let columns = heroColumns(for: config.heroStats.count)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(config.heroStats) { stat in
                    BragHeroCard(
                        stat: stat,
                        value: result?.value(for: stat),
                        isLoading: bragStats.isComputing
                    )
                }
            }
        }
    }

    private func heroColumns(for count: Int) -> [GridItem] {
        let columnCount = min(count, 2)
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }
}

// MARK: - BragHeroCard

/// Large card for hero-promoted stats. Shows icon, stat name, large value, subtitle.
struct BragHeroCard: View {
    // MARK: Internal

    let stat: BragSheetStatType
    let value: BragSheetStatValue?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Icon + stat name
            HStack(spacing: 6) {
                Image(systemName: stat.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(stat.displayName)
                    .font(.caption)
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
                // Hero value (large)
                heroValueText

                // Subtitle
                if let subtitle = displayValue.subtitleDisplay {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private var displayValue: BragSheetStatValue {
        value ?? .noData
    }

    @ViewBuilder
    private var heroValueText: some View {
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
            .font(.title2)
            .fontWeight(.bold)
            .fontDesign(isContactType ? .monospaced : .default)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .opacity(isNoData || isLoading ? 0.6 : 1.0)
    }
}
