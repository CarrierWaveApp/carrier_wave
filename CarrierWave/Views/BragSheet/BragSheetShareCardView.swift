// Brag Sheet Share Card View
//
// Dedicated share card for brag sheet stats, themed to match the activation share card.
// Shows header, stat grid with all enabled stats, optional statistician section, and footer.

import CarrierWaveData
import SwiftUI
import UIKit

// MARK: - BragSheetShareCardView

struct BragSheetShareCardView: View {
    // MARK: Internal

    let result: BragSheetComputedResult
    let config: BragSheetPeriodConfig
    let period: BragSheetPeriod
    let callsign: String
    var mapImage: UIImage?
    var statisticianStats: BragSheetStatisticianData?

    var body: some View {
        VStack(spacing: 0) {
            header
            periodLabel
            mapSection
            heroStatsSection
            gridStatsSection
            if let stats = statisticianStats {
                BragSheetStatisticianSection(stats: stats)
                    .padding(.top, 6)
            }
            footer
        }
        .frame(width: 400, height: cardHeight)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.10, blue: 0.18),
                    Color(red: 0.18, green: 0.12, blue: 0.25),
                    Color(red: 0.12, green: 0.10, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(Rectangle())
    }

    // MARK: Private

    // MARK: - Layout

    private var cardHeight: CGFloat {
        let base: CGFloat = 200 // header + period + footer
        let mapSectionHeight: CGFloat = mapImage != nil ? 216 : 0
        let heroes = activeHeroStats
        let heroHeight: CGFloat = heroes.isEmpty ? 0 : 80
        let gridStats = activeGridStats
        let gridRows = (gridStats.count + 1) / 2
        let gridHeight = CGFloat(gridRows) * 42
        let statisticianHeight: CGFloat = statisticianStats != nil ? 170 : 0
        return base + mapSectionHeight + heroHeight + gridHeight + statisticianHeight
    }

    /// Hero stats that actually have a displayable value.
    private var activeHeroStats: [BragSheetStatType] {
        Array(config.heroStats.prefix(4).filter {
            result.value(for: $0).isShareable
        })
    }

    /// Grid stats (non-hero, enabled) that actually have a displayable value.
    private var activeGridStats: [BragSheetStatType] {
        let heroSet = Set(config.heroStats)
        return config.enabledStats.filter {
            !heroSet.contains($0) && result.value(for: $0).isShareable
        }
    }

    private var headlineText: String {
        switch period {
        case .weekly: "Last 7 Days in Radio"
        case .monthly: "My Month in Radio"
        case .allTime: "All-Time Stats"
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("CARRIER WAVE")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.top, 24)

            Text(headlineText)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.top, 4)
        }
    }

    // MARK: - Period Label

    private var periodLabel: some View {
        Text(period.periodLabel())
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.top, 2)
            .padding(.bottom, 12)
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        if let mapImage {
            Image(uiImage: mapImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Hero Stats

    private var heroStatsSection: some View {
        let heroes = activeHeroStats
        return Group {
            if !heroes.isEmpty {
                HStack(spacing: 8) {
                    ForEach(heroes, id: \.self) { stat in
                        bragHeroItem(
                            value: result.value(for: stat).heroValue,
                            label: stat.shortDisplayName
                        )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color.purple.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Grid Stats

    private var gridStatsSection: some View {
        let gridStats = activeGridStats
        return Group {
            if !gridStats.isEmpty {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ],
                    spacing: 6
                ) {
                    ForEach(gridStats, id: \.self) { stat in
                        gridStatCell(stat)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text(callsign)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.top, 16)
            .padding(.bottom, 24)
    }

    private func bragHeroItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func gridStatCell(_ stat: BragSheetStatType) -> some View {
        let value = result.value(for: stat)
        return HStack(spacing: 6) {
            Image(systemName: stat.systemImage)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 1) {
                Text(value.heroValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(stat.displayName)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
